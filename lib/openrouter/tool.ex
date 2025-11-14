defmodule Openrouter.Tool do
  @moduledoc """
  Defines tools (functions) that can be called by LLMs.

  Tools enable LLMs to interact with external systems, databases, APIs, and
  custom Elixir functions. This is the foundation for agentic workflows.

  ## Basic Usage

      # Define a simple tool
      weather_tool = Openrouter.Tool.new(
        :get_weather,
        "Get the current weather for a location",
        fn %{location: location} ->
          {:ok, "The weather in #{location} is sunny, 72°F"}
        end,
        parameters: %{
          location: [type: :string, description: "City name", required: true],
          unit: [type: :string, enum: ["celsius", "fahrenheit"]]
        }
      )

      # Use with chat
      {:ok, result} = Openrouter.chat(
        "What's the weather in Paris?",
        model: "openai/gpt-4",
        tools: [weather_tool]
      )

  ## With Dependencies (RunContext)

      # Tool that needs database access
      balance_tool = Openrouter.Tool.new(
        :get_balance,
        "Get customer account balance",
        fn ctx, %{include_pending: pending} ->
          # ctx.deps contains your dependencies
          balance = DB.get_balance(ctx.deps.db, ctx.deps.customer_id, pending)
          {:ok, balance}
        end,
        parameters: %{
          include_pending: [type: :boolean, description: "Include pending transactions"]
        }
      )

  ## Parameter Types

  Supported parameter types:
  - `:string` - String values
  - `:integer` - Integer numbers
  - `:number` - Float or integer numbers
  - `:boolean` - true/false
  - `:array` - Array of items (specify item type with `items:`)
  - `:object` - Nested object (specify properties with `properties:`)

  ## Examples

      # String parameter with enum
      parameters: %{
        status: [type: :string, enum: ["active", "pending", "closed"]]
      }

      # Array of strings
      parameters: %{
        tags: [type: :array, items: :string]
      }

      # Nested object
      parameters: %{
        address: [
          type: :object,
          properties: %{
            street: [type: :string],
            city: [type: :string]
          }
        ]
      }

      # Multiple parameters with required fields
      parameters: %{
        name: [type: :string, required: true],
        age: [type: :integer, required: true],
        email: [type: :string]
      }
  """

  @type parameter_type :: :string | :integer | :number | :boolean | :array | :object
  @type parameter_spec :: [
          type: parameter_type(),
          description: String.t(),
          required: boolean(),
          enum: [any()],
          items: parameter_type() | parameter_spec(),
          properties: %{atom() => parameter_spec()}
        ]

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t(),
          function: function(),
          parameters: %{atom() => parameter_spec()},
          context_aware: boolean()
        }

  defstruct [:name, :description, :function, :parameters, context_aware: false]

  @doc """
  Creates a new tool definition.

  ## Arguments

    * `name` - Atom identifying the tool (e.g., `:get_weather`)
    * `description` - Human-readable description of what the tool does
    * `function` - Function to execute when tool is called
    * `opts` - Options (see below)

  ## Options

    * `:parameters` - Map of parameter names to specifications
    * `:context_aware` - Whether function receives RunContext as first arg (default: false)

  ## Examples

      # Simple tool (no parameters)
      tool = Openrouter.Tool.new(
        :get_time,
        "Get the current time",
        fn -> {:ok, DateTime.utc_now() |> to_string()} end
      )

      # Tool with parameters
      tool = Openrouter.Tool.new(
        :calculate,
        "Perform a calculation",
        fn %{operation: op, a: a, b: b} ->
          result = case op do
            "add" -> a + b
            "multiply" -> a * b
          end
          {:ok, result}
        end,
        parameters: %{
          operation: [type: :string, enum: ["add", "multiply"], required: true],
          a: [type: :number, required: true],
          b: [type: :number, required: true]
        }
      )

      # Context-aware tool (receives RunContext)
      tool = Openrouter.Tool.new(
        :get_user_data,
        "Get data for current user",
        fn ctx, %{field: field} ->
          # ctx.deps contains dependencies
          user_id = ctx.deps.user_id
          {:ok, DB.get_user_field(user_id, field)}
        end,
        parameters: %{
          field: [type: :string, required: true]
        },
        context_aware: true
      )
  """
  @spec new(atom(), String.t(), function(), keyword()) :: t()
  def new(name, description, function, opts \\ []) do
    %__MODULE__{
      name: name,
      description: description,
      function: function,
      parameters: Keyword.get(opts, :parameters, %{}),
      context_aware: Keyword.get(opts, :context_aware, false)
    }
  end

  @doc """
  Converts a tool to OpenAI function calling format.

  This is used internally to send tools to the LLM.
  """
  @spec to_openai_format(t()) :: map()
  def to_openai_format(%__MODULE__{} = tool) do
    %{
      type: "function",
      function: %{
        name: to_string(tool.name),
        description: tool.description,
        parameters: build_parameters_schema(tool.parameters)
      }
    }
  end

  @doc """
  Executes a tool with the given arguments.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.

  ## Examples

      tool = Openrouter.Tool.new(:add, "Add numbers", fn %{a: a, b: b} ->
        {:ok, a + b}
      end)

      {:ok, result} = Openrouter.Tool.execute(tool, %{a: 5, b: 3})
      # => {:ok, 8}
  """
  @spec execute(t(), map(), any()) :: {:ok, any()} | {:error, any()}
  def execute(%__MODULE__{} = tool, arguments, context \\ nil) do
    try do
      # Convert string keys to atoms for function arguments
      args = atomize_keys(arguments)

      result =
        if tool.context_aware do
          # Context-aware function receives context as first argument
          tool.function.(context, args)
        else
          # Regular function just gets arguments
          tool.function.(args)
        end

      # Normalize result
      case result do
        {:ok, _} = success -> success
        {:error, _} = error -> error
        value -> {:ok, value}
      end
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  @doc """
  Validates that arguments match the tool's parameter schema.

  Returns `:ok` if valid, `{:error, reason}` if invalid.
  """
  @spec validate_arguments(t(), map()) :: :ok | {:error, String.t()}
  def validate_arguments(%__MODULE__{} = tool, arguments) do
    # Check required parameters
    required_params =
      tool.parameters
      |> Enum.filter(fn {_name, spec} -> Keyword.get(spec, :required, false) end)
      |> Enum.map(fn {name, _spec} -> to_string(name) end)

    missing =
      Enum.filter(required_params, fn param ->
        not Map.has_key?(arguments, param) and not Map.has_key?(arguments, String.to_atom(param))
      end)

    if missing != [] do
      {:error, "Missing required parameters: #{Enum.join(missing, ", ")}"}
    else
      :ok
    end
  end

  # Private functions

  defp build_parameters_schema(parameters) when parameters == %{} do
    %{
      type: "object",
      properties: %{}
    }
  end

  defp build_parameters_schema(parameters) do
    properties =
      parameters
      |> Enum.map(fn {name, spec} ->
        {name, build_property_schema(spec)}
      end)
      |> Map.new()

    required =
      parameters
      |> Enum.filter(fn {_name, spec} -> Keyword.get(spec, :required, false) end)
      |> Enum.map(fn {name, _spec} -> to_string(name) end)

    schema = %{
      type: "object",
      properties: properties
    }

    if required != [] do
      Map.put(schema, :required, required)
    else
      schema
    end
  end

  defp build_property_schema(spec) do
    type = Keyword.fetch!(spec, :type)

    schema = %{type: type_to_string(type)}

    schema =
      if description = Keyword.get(spec, :description) do
        Map.put(schema, :description, description)
      else
        schema
      end

    schema =
      if enum = Keyword.get(spec, :enum) do
        Map.put(schema, :enum, enum)
      else
        schema
      end

    schema =
      if type == :array do
        items = Keyword.get(spec, :items, :string)

        items_schema =
          if is_atom(items) do
            %{type: type_to_string(items)}
          else
            build_property_schema(items)
          end

        Map.put(schema, :items, items_schema)
      else
        schema
      end

    schema =
      if type == :object do
        if properties = Keyword.get(spec, :properties) do
          nested_properties =
            properties
            |> Enum.map(fn {name, prop_spec} ->
              {name, build_property_schema(prop_spec)}
            end)
            |> Map.new()

          Map.put(schema, :properties, nested_properties)
        else
          schema
        end
      else
        schema
      end

    schema
  end

  defp type_to_string(:string), do: "string"
  defp type_to_string(:integer), do: "integer"
  defp type_to_string(:number), do: "number"
  defp type_to_string(:boolean), do: "boolean"
  defp type_to_string(:array), do: "array"
  defp type_to_string(:object), do: "object"

  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
    |> Map.new()
  end
end
