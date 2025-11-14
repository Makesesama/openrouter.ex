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
    if function_exported?(schema_module, :__schema__, 1) do
      fields = schema_module.__schema__(:fields)
      types = schema_module.__schema__(:types)
      embeds = schema_module.__schema__(:embeds)

      properties =
        fields
        |> Enum.map(fn field ->
          field_type = Map.get(types, field)

          # Check if this is an embedded schema
          json_type = if field in embeds do
            embed_type = schema_module.__schema__(:embed, field)
            ecto_embed_to_json_type(embed_type)
          else
            ecto_type_to_json_type(field_type, schema_module)
          end

          {field, json_type}
        end)
        |> Map.new()

      # Get required fields from changeset if available
      required_fields = get_required_fields(schema_module)

      schema = %{
        type: "object",
        properties: properties
      }

      if required_fields != [] do
        Map.put(schema, :required, required_fields)
      else
        schema
      end
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
  """
  @spec format_errors(Ecto.Changeset.t()) :: String.t()
  def format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end

  # Private helpers

  defp ecto_type_to_json_type(:string, _schema), do: %{type: "string"}
  defp ecto_type_to_json_type(:integer, _schema), do: %{type: "integer"}
  defp ecto_type_to_json_type(:float, _schema), do: %{type: "number"}
  defp ecto_type_to_json_type(:boolean, _schema), do: %{type: "boolean"}
  defp ecto_type_to_json_type(:decimal, _schema), do: %{type: "number"}
  defp ecto_type_to_json_type(:date, _schema), do: %{type: "string", format: "date"}
  defp ecto_type_to_json_type(:time, _schema), do: %{type: "string", format: "time"}
  defp ecto_type_to_json_type(:naive_datetime, _schema), do: %{type: "string", format: "date-time"}
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
    to_json_schema(related_module)
  end

  defp ecto_embed_to_json_type(%Ecto.Embedded{cardinality: :many, related: related_module}) do
    # embeds_many: generate array of nested objects
    %{
      type: "array",
      items: to_json_schema(related_module)
    }
  end

  defp get_required_fields(schema_module) do
    if function_exported?(schema_module, :changeset, 2) do
      # Try to infer required fields from changeset
      # This is a best-effort approach
      []
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
