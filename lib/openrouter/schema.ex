defmodule Openrouter.Schema do
  @moduledoc """
  Defines schemas for structured outputs with Ecto integration.

  This module provides a way to define schemas that can be used to extract
  structured data from LLM responses with automatic validation and retry.

  Supports nested schemas with `embeds_one` and `embeds_many` for complex
  hierarchical data structures.

  ## Basic Usage

      defmodule UserSchema do
        use Openrouter.Schema

        embedded_schema do
          field :name, :string
          field :age, :integer
          field :email, :string
        end

        def changeset(schema, attrs) do
          schema
          |> cast(attrs, [:name, :age, :email])
          |> validate_required([:name, :age])
          |> validate_format(:email, ~r/@/)
        end
      end

      # Extract structured data
      {:ok, user} = Openrouter.extract(
        "Extract: John Doe is 30 years old, email john@example.com",
        schema: UserSchema,
        model: "openai/gpt-4"
      )

      # user is a validated UserSchema struct
      IO.puts(user.name)  # "John Doe"
      IO.puts(user.age)   # 30

  ## Nested Schemas

      defmodule AddressSchema do
        use Openrouter.Schema

        embedded_schema do
          field :street, :string
          field :city, :string
          field :country, :string
          field :zip_code, :string
        end

        def changeset(schema, attrs) do
          schema
          |> cast(attrs, [:street, :city, :country, :zip_code])
          |> validate_required([:city, :country])
        end
      end

      defmodule PersonSchema do
        use Openrouter.Schema

        embedded_schema do
          field :name, :string
          field :age, :integer
          embeds_one :address, AddressSchema
          embeds_many :phone_numbers, PhoneSchema
        end

        def changeset(schema, attrs) do
          schema
          |> cast(attrs, [:name, :age])
          |> cast_embed(:address)
          |> cast_embed(:phone_numbers)
          |> validate_required([:name])
        end
      end

      # Extract with nested data
      {:ok, person} = Openrouter.extract(
        "John Doe, 30 years old, lives at 123 Main St, New York, USA, 10001",
        schema: PersonSchema,
        model: "openai/gpt-4"
      )

      IO.puts(person.address.city)  # "New York"
  """

  @doc """
  Generates a JSON schema from an Ecto schema module.

  This is used internally to provide the LLM with the structure it should follow.

  Supports:
  - Basic types (string, integer, float, boolean, etc.)
  - Arrays (`{:array, type}`)
  - Nested schemas (`embeds_one`, `embeds_many`)
  - Maps and complex structures
  """
  @spec to_json_schema(module()) :: map()
  def to_json_schema(schema_module) do
    to_json_schema(schema_module, strict: true)
  end

  @spec to_json_schema(module(), keyword()) :: map()
  def to_json_schema(schema_module, opts) do
    if function_exported?(schema_module, :__schema__, 1) do
      fields = schema_module.__schema__(:fields)
      embeds = schema_module.__schema__(:embeds)
      strict = Keyword.get(opts, :strict, true)

      properties =
        fields
        |> Enum.map(&build_field_property(&1, schema_module, embeds))
        |> Map.new()

      # For strict mode with OpenRouter/OpenAI:
      # - In strict: true mode, ALL properties MUST be in required array (no optional fields)
      # - In strict: false mode, only validated required fields are in required array
      # - additionalProperties must be false

      required_fields =
        if strict do
          # In strict mode, ALL fields must be required
          Enum.map(fields, &Atom.to_string/1)
        else
          # In non-strict mode, only get required fields from changeset
          get_required_fields_from_changeset(schema_module)
        end

      %{
        type: "object",
        properties: properties,
        required: required_fields,
        additionalProperties: false
      }
    else
      raise ArgumentError, "#{inspect(schema_module)} is not an Ecto schema"
    end
  end

  @doc """
  Validates data against an Ecto schema and returns a struct.

  Returns `{:ok, struct}` if validation succeeds, `{:error, changeset}` otherwise.
  """
  @spec validate(module(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def validate(schema_module, data) when is_map(data) do
    changeset_fun =
      if function_exported?(schema_module, :changeset, 2) do
        &schema_module.changeset/2
      else
        &default_changeset/2
      end

    changeset = changeset_fun.(struct(schema_module), data)

    if changeset.valid? do
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      {:error, changeset}
    end
  end

  @doc """
  Formats validation errors from a changeset into a readable string.

  This is used to provide feedback to the LLM when retrying.
  Handles nested changesets from embeds_one and embeds_many.
  """
  @spec format_errors(Ecto.Changeset.t()) :: String.t()
  def format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", format_error_value(value))
      end)
    end)
    |> format_error_map()
  end

  defp format_error_value(value) when is_binary(value), do: value
  defp format_error_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_error_value(value) when is_float(value), do: Float.to_string(value)
  defp format_error_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_error_value(value) when is_list(value), do: inspect(value)
  defp format_error_value(value) when is_tuple(value), do: inspect(value)
  defp format_error_value(value), do: inspect(value)

  defp format_error_map(errors) when is_map(errors) do
    errors
    |> Enum.map_join("; ", fn {field, field_errors} ->
      format_field_errors(field, field_errors)
    end)
  end

  defp format_field_errors(field, errors) when is_list(errors) do
    # Check if it's a list of strings (simple errors) or list of maps (nested errors)
    case errors do
      [first | _] when is_binary(first) ->
        # Simple string errors
        "#{field}: #{Enum.join(errors, ", ")}"

      [first | _] when is_map(first) ->
        # Nested errors from embeds_many
        nested_errors =
          errors
          |> Enum.with_index()
          |> Enum.map_join("; ", fn {nested_map, idx} ->
            "#{field}[#{idx}]: #{format_error_map(nested_map)}"
          end)

        nested_errors

      [] ->
        ""
    end
  end

  defp format_field_errors(field, nested_map) when is_map(nested_map) do
    # Nested errors from embeds_one
    "#{field}: #{format_error_map(nested_map)}"
  end

  defp format_field_errors(field, error) when is_binary(error) do
    "#{field}: #{error}"
  end

  # Private helpers

  defp build_field_property(field, schema_module, embeds) do
    field_type = schema_module.__schema__(:type, field)

    json_type =
      if field in embeds do
        embed_type = schema_module.__schema__(:embed, field)
        ecto_embed_to_json_type(embed_type)
      else
        ecto_type_to_json_type(field_type, schema_module)
      end

    {field, json_type}
  end

  defp ecto_type_to_json_type(:string, _schema), do: %{type: "string"}
  defp ecto_type_to_json_type(:integer, _schema), do: %{type: "integer"}
  defp ecto_type_to_json_type(:float, _schema), do: %{type: "number"}
  defp ecto_type_to_json_type(:boolean, _schema), do: %{type: "boolean"}
  defp ecto_type_to_json_type(:decimal, _schema), do: %{type: "number"}
  defp ecto_type_to_json_type(:date, _schema), do: %{type: "string", format: "date"}
  defp ecto_type_to_json_type(:time, _schema), do: %{type: "string", format: "time"}

  defp ecto_type_to_json_type(:naive_datetime, _schema),
    do: %{type: "string", format: "date-time"}

  defp ecto_type_to_json_type(:utc_datetime, _schema), do: %{type: "string", format: "date-time"}

  defp ecto_type_to_json_type({:array, inner_type}, schema) do
    %{type: "array", items: ecto_type_to_json_type(inner_type, schema)}
  end

  defp ecto_type_to_json_type({:map, _}, _schema), do: %{type: "object"}
  defp ecto_type_to_json_type(:map, _schema), do: %{type: "object"}
  defp ecto_type_to_json_type(_, _schema), do: %{type: "string"}

  # Handle embedded schemas (embeds_one and embeds_many)
  defp ecto_embed_to_json_type(%Ecto.Embedded{cardinality: :one, related: related_module}) do
    # embeds_one: generate nested object schema
    # Always use strict mode for nested schemas
    to_json_schema(related_module, strict: true)
  end

  defp ecto_embed_to_json_type(%Ecto.Embedded{cardinality: :many, related: related_module}) do
    # embeds_many: generate array of nested objects
    # Always use strict mode for nested schemas
    %{
      type: "array",
      items: to_json_schema(related_module, strict: true)
    }
  end

  defp get_required_fields_from_changeset(schema_module) do
    if function_exported?(schema_module, :changeset, 2) do
      # Try to infer required fields by running changeset with empty data
      # and checking which fields have "can't be blank" errors
      try do
        changeset = schema_module.changeset(struct(schema_module), %{})

        if changeset.valid? do
          # No required fields
          []
        else
          # Extract fields with "can't be blank" or "is required" errors
          changeset.errors
          |> Enum.filter(fn {_field, {msg, _opts}} ->
            msg =~ "can't be blank" or msg =~ "is required"
          end)
          |> Enum.map(fn {field, _} -> Atom.to_string(field) end)
        end
      rescue
        _ -> []
      end
    else
      []
    end
  end

  defp default_changeset(schema, attrs) do
    import Ecto.Changeset

    fields = schema.__struct__.__schema__(:fields)
    cast(schema, attrs, fields)
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key false
    end
  end
end
