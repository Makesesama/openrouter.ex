defmodule Openrouter.Schema do
  @moduledoc """
  Defines schemas for structured outputs with Ecto integration.

  This module provides a way to define schemas that can be used to extract
  structured data from LLM responses with automatic validation and retry.

  ## Usage

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
  """

  @doc """
  Generates a JSON schema from an Ecto schema module.

  This is used internally to provide the LLM with the structure it should follow.
  """
  @spec to_json_schema(module()) :: map()
  def to_json_schema(schema_module) do
    if function_exported?(schema_module, :__schema__, 1) do
      fields = schema_module.__schema__(:fields)
      types = schema_module.__schema__(:types)

      properties =
        fields
        |> Enum.map(fn field ->
          field_type = Map.get(types, field)
          {field, ecto_type_to_json_type(field_type)}
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

  defp ecto_type_to_json_type(:string), do: %{type: "string"}
  defp ecto_type_to_json_type(:integer), do: %{type: "integer"}
  defp ecto_type_to_json_type(:float), do: %{type: "number"}
  defp ecto_type_to_json_type(:boolean), do: %{type: "boolean"}
  defp ecto_type_to_json_type(:decimal), do: %{type: "number"}
  defp ecto_type_to_json_type(:date), do: %{type: "string", format: "date"}
  defp ecto_type_to_json_type(:time), do: %{type: "string", format: "time"}
  defp ecto_type_to_json_type(:naive_datetime), do: %{type: "string", format: "date-time"}
  defp ecto_type_to_json_type(:utc_datetime), do: %{type: "string", format: "date-time"}
  defp ecto_type_to_json_type({:array, inner_type}) do
    %{type: "array", items: ecto_type_to_json_type(inner_type)}
  end
  defp ecto_type_to_json_type({:map, _}), do: %{type: "object"}
  defp ecto_type_to_json_type(:map), do: %{type: "object"}
  defp ecto_type_to_json_type(_), do: %{type: "string"}

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
