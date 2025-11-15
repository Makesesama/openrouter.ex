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
        fn %{location: loc} ->
          {:ok, "The weather in " <> loc <> " is sunny, 72°F"}
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

  Tools can be context-aware, receiving a `RunContext` struct as their first
  argument. This enables type-safe dependency injection for database connections,
  user context, and other runtime dependencies.

      # Define your dependencies
      defmodule AppDeps do
        defstruct [:db_conn, :customer_id, :user]
      end

      # Tool that receives RunContext
      balance_tool = Openrouter.Tool.new(
        :get_balance,
        "Get customer account balance",
        fn ctx, %{include_pending: pending} ->
          # ctx is a RunContext struct
          # ctx.deps contains your AppDeps struct
          balance = DB.get_balance(
            ctx.deps.db_conn,
            ctx.deps.customer_id,
            include_pending: pending
          )
          {:ok, balance}
        end,
        parameters: %{
          include_pending: [type: :boolean, description: "Include pending transactions"]
        },
        context_aware: true  # Important!
      )

      # Use with dependencies
      deps = %AppDeps{
        db_conn: MyApp.Repo,
        customer_id: 123,
        user: current_user
      }

      {:ok, result} = Openrouter.Agent.run(
        "What's my balance?",
        model: "gpt-4",
        tools: [balance_tool],
        deps: deps
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

  alias Openrouter.RunContext

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

  For context-aware tools, pass a `RunContext` struct as the third argument.
  The tool function will receive the RunContext as its first parameter.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.

  ## Examples

      # Regular tool
      tool = Openrouter.Tool.new(:add, "Add numbers", fn %{a: a, b: b} ->
        {:ok, a + b}
      end)

      {:ok, result} = Openrouter.Tool.execute(tool, %{a: 5, b: 3})
      # => {:ok, 8}

      # Context-aware tool
      tool = Openrouter.Tool.new(
        :get_user,
        "Get user data",
        fn ctx, %{field: field} ->
          {:ok, Map.get(ctx.deps.user, field)}
        end,
        context_aware: true
      )

      ctx = RunContext.new(deps: %{user: %{name: "Alice"}})
      {:ok, name} = Openrouter.Tool.execute(tool, %{field: :name}, ctx)
      # => {:ok, "Alice"}
  """
  @spec execute(t(), map(), RunContext.t() | nil) :: {:ok, any()} | {:error, any()}
  def execute(%__MODULE__{} = tool, arguments, context \\ nil) do
    # First validate arguments
    case validate_arguments(tool, arguments) do
      :ok ->
        try do
          # Convert string keys to atoms for function arguments
          args = atomize_keys(arguments)

          result =
            if tool.context_aware do
              # Check if context is provided for context-aware tools
              if is_nil(context) do
                {:error, "Context required for context-aware tool"}
              else
                # Context-aware function receives args as first argument, context as second
                tool.function.(args, context)
              end
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

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates that arguments match the tool's parameter schema.

  Returns `:ok` if valid, `{:error, reason}` if invalid.
  """
  @spec validate_arguments(t(), map()) :: :ok | {:error, String.t()}
  def validate_arguments(%__MODULE__{} = tool, arguments) do
    # Convert arguments to atom keys for consistent checking
    args = atomize_keys(arguments)

    # Check required parameters
    required_params =
      tool.parameters
      |> Enum.filter(fn {_name, spec} -> Keyword.get(spec, :required, false) end)
      |> Enum.map(fn {name, _spec} -> name end)

    missing =
      Enum.filter(required_params, fn param ->
        not Map.has_key?(args, param)
      end)

    if missing != [] do
      {:error, "Missing required parameters: #{Enum.join(missing, ", ")}"}
    else
      # Validate types for provided parameters
      validate_types(args, tool.parameters)
    end
  end

  # Validate parameter types
  defp validate_types(args, parameters) do
    Enum.reduce_while(parameters, :ok, fn {name, spec}, _acc ->
      validate_parameter(args, name, spec)
    end)
  end

  defp validate_parameter(args, name, spec) do
    value = Map.get(args, name)
    required = Keyword.get(spec, :required, false)

    if is_nil(value) and not required do
      {:cont, :ok}
    else
      case validate_type(name, value, spec) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end
  end

  defp validate_type(name, value, spec) do
    type = Keyword.get(spec, :type, :string)

    with :ok <- validate_type_match(name, value, type) do
      validate_enum_constraint(name, value, spec)
    end
  end

  defp validate_type_match(name, value, type) do
    type_valid = check_type_match(value, type)

    if type_valid do
      :ok
    else
      {:error, "Parameter '#{name}' must be #{format_type_name(type)}"}
    end
  end

  defp check_type_match(value, type) do
    case type do
      :string -> is_binary(value)
      :integer -> is_integer(value)
      :number -> is_number(value)
      :boolean -> is_boolean(value)
      :array -> is_list(value)
      :object -> is_map(value)
      _ -> true
    end
  end

  defp format_type_name(type) do
    case type do
      :number -> "a number"
      :integer -> "an integer"
      :array -> "an array"
      :object -> "an object"
      _ -> "a #{type}"
    end
  end

  defp validate_enum_constraint(name, value, spec) do
    case Keyword.get(spec, :enum) do
      nil -> :ok
      enum -> validate_enum_value(name, value, enum)
    end
  end

  defp validate_enum_value(name, value, enum) do
    if value in enum do
      :ok
    else
      {:error, "Parameter '#{name}' must be one of: #{Enum.join(enum, ", ")}"}
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

    %{
      type: "object",
      properties: properties,
      required: required
    }
  end

  defp build_property_schema(spec) when is_list(spec) do
    type = Keyword.fetch!(spec, :type)
    schema = build_base_schema_keyword(spec, type)

    schema
    |> add_array_items_from_keyword(spec, type)
    |> add_object_properties_from_keyword(spec, type)
  end

  defp build_base_schema_keyword(spec, type) do
    schema = %{type: type_to_string(type)}

    schema
    |> add_description_from_keyword(spec)
    |> add_enum_from_keyword(spec)
  end

  defp add_description_from_keyword(schema, spec) do
    case Keyword.get(spec, :description) do
      nil -> schema
      description -> Map.put(schema, :description, description)
    end
  end

  defp add_enum_from_keyword(schema, spec) do
    case Keyword.get(spec, :enum) do
      nil -> schema
      enum -> Map.put(schema, :enum, enum)
    end
  end

  defp add_array_items_from_keyword(schema, spec, :array) do
    items = Keyword.get(spec, :items, :string)
    items_schema = build_items_schema(items)
    Map.put(schema, :items, items_schema)
  end

  defp add_array_items_from_keyword(schema, _spec, _type), do: schema

  defp add_object_properties_from_keyword(schema, spec, :object) do
    case Keyword.get(spec, :properties) do
      nil -> schema
      properties -> Map.put(schema, :properties, build_nested_properties(properties))
    end
  end

  defp add_object_properties_from_keyword(schema, _spec, _type), do: schema

  defp build_property_schema_from_map(spec) when is_map(spec) do
    type = Map.get(spec, :type, :string)
    schema = build_base_schema_map(spec, type)

    schema
    |> add_array_items_if_needed(spec, type)
    |> add_object_properties_if_needed(spec, type)
  end

  defp build_base_schema_map(spec, type) do
    schema = %{type: type_to_string(type)}

    schema
    |> add_description_if_present(spec)
    |> add_enum_if_present(spec)
  end

  defp add_description_if_present(schema, spec) do
    case Map.get(spec, :description) do
      nil -> schema
      description -> Map.put(schema, :description, description)
    end
  end

  defp add_enum_if_present(schema, spec) do
    case Map.get(spec, :enum) do
      nil -> schema
      enum -> Map.put(schema, :enum, enum)
    end
  end

  defp add_array_items_if_needed(schema, spec, :array) do
    items = Map.get(spec, :items, :string)
    items_schema = build_items_schema(items)
    Map.put(schema, :items, items_schema)
  end

  defp add_array_items_if_needed(schema, _spec, _type), do: schema

  defp build_items_schema(atom) when is_atom(atom) do
    %{type: type_to_string(atom)}
  end

  defp build_items_schema(items_spec) when is_list(items_spec) do
    build_property_schema(items_spec)
  end

  defp build_items_schema(items_spec) when is_map(items_spec) do
    build_property_schema_from_map(items_spec)
  end

  defp add_object_properties_if_needed(schema, spec, :object) do
    case Map.get(spec, :properties) do
      nil -> schema
      properties -> Map.put(schema, :properties, build_nested_properties(properties))
    end
  end

  defp add_object_properties_if_needed(schema, _spec, _type), do: schema

  defp build_nested_properties(properties) do
    properties
    |> Enum.map(&build_property_entry/1)
    |> Map.new()
  end

  defp build_property_entry({name, spec}) when is_list(spec) do
    {name, build_property_schema(spec)}
  end

  defp build_property_entry({name, spec}) when is_map(spec) do
    {name, build_property_schema_from_map(spec)}
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
