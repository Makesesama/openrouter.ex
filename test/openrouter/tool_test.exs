defmodule Openrouter.ToolTest do
  use ExUnit.Case, async: true

  alias Openrouter.Tool

  describe "Tool.new/4" do
    test "creates a basic tool" do
      tool =
        Tool.new(
          :test_tool,
          "A test tool",
          fn %{arg: value} -> {:ok, value} end
        )

      assert tool.name == :test_tool
      assert tool.description == "A test tool"
      assert is_function(tool.function, 1)
      assert tool.parameters == %{}
      assert tool.context_aware == false
    end

    test "creates a tool with parameters" do
      tool =
        Tool.new(
          :calculator,
          "Performs calculations",
          fn %{a: a, b: b} -> {:ok, a + b} end,
          parameters: %{
            a: [type: :number, required: true],
            b: [type: :number, required: true]
          }
        )

      assert tool.parameters == %{
               a: [type: :number, required: true],
               b: [type: :number, required: true]
             }
    end

    test "creates a context-aware tool" do
      tool =
        Tool.new(
          :get_user,
          "Gets current user",
          fn _params, ctx -> {:ok, ctx.user} end,
          context_aware: true
        )

      assert tool.context_aware == true
    end
  end

  describe "Tool.to_openai_format/1" do
    test "converts simple tool to OpenAI format" do
      tool =
        Tool.new(
          :test_tool,
          "A test tool",
          fn _ -> {:ok, "result"} end
        )

      format = Tool.to_openai_format(tool)

      assert format.type == "function"
      assert format.function.name == "test_tool"
      assert format.function.description == "A test tool"
      assert format.function.parameters == %{type: "object", properties: %{}}
    end

    test "converts tool with string parameters" do
      tool =
        Tool.new(
          :greet,
          "Greets a person",
          fn %{name: name} -> {:ok, "Hello, #{name}!"} end,
          parameters: %{
            name: [type: :string, required: true, description: "Person's name"]
          }
        )

      format = Tool.to_openai_format(tool)

      assert format.function.parameters.type == "object"
      assert format.function.parameters.properties.name.type == "string"
      assert format.function.parameters.properties.name.description == "Person's name"
      assert format.function.parameters.required == ["name"]
    end

    test "converts tool with number parameters" do
      tool =
        Tool.new(
          :calculator,
          "Adds numbers",
          fn %{a: a, b: b} -> {:ok, a + b} end,
          parameters: %{
            a: [type: :number, required: true],
            b: [type: :integer, required: false]
          }
        )

      format = Tool.to_openai_format(tool)

      assert format.function.parameters.properties.a.type == "number"
      assert format.function.parameters.properties.b.type == "integer"
      assert format.function.parameters.required == ["a"]
    end

    test "converts tool with boolean parameters" do
      tool =
        Tool.new(
          :toggle,
          "Toggles a setting",
          fn %{enabled: enabled} -> {:ok, enabled} end,
          parameters: %{
            enabled: [type: :boolean, required: true]
          }
        )

      format = Tool.to_openai_format(tool)

      assert format.function.parameters.properties.enabled.type == "boolean"
    end

    test "converts tool with array parameters" do
      tool =
        Tool.new(
          :process_items,
          "Processes a list of items",
          fn %{items: items} -> {:ok, length(items)} end,
          parameters: %{
            items: [
              type: :array,
              required: true,
              description: "List of items",
              items: %{type: :string}
            ]
          }
        )

      format = Tool.to_openai_format(tool)

      assert format.function.parameters.properties.items.type == "array"
      assert format.function.parameters.properties.items.items.type == "string"
      assert format.function.parameters.properties.items.description == "List of items"
    end

    test "converts tool with object parameters" do
      tool =
        Tool.new(
          :create_user,
          "Creates a user",
          fn %{user: user} -> {:ok, user} end,
          parameters: %{
            user: [
              type: :object,
              required: true,
              properties: %{
                name: %{type: :string},
                age: %{type: :integer}
              }
            ]
          }
        )

      format = Tool.to_openai_format(tool)

      assert format.function.parameters.properties.user.type == "object"
      assert format.function.parameters.properties.user.properties.name.type == "string"
      assert format.function.parameters.properties.user.properties.age.type == "integer"
    end

    test "includes enum values" do
      tool =
        Tool.new(
          :set_mode,
          "Sets operation mode",
          fn %{mode: mode} -> {:ok, mode} end,
          parameters: %{
            mode: [type: :string, required: true, enum: ["fast", "slow", "auto"]]
          }
        )

      format = Tool.to_openai_format(tool)

      assert format.function.parameters.properties.mode.enum == ["fast", "slow", "auto"]
    end

    test "handles optional parameters" do
      tool =
        Tool.new(
          :search,
          "Searches items",
          fn params -> {:ok, params} end,
          parameters: %{
            query: [type: :string, required: true],
            limit: [type: :integer, required: false],
            offset: [type: :integer, required: false]
          }
        )

      format = Tool.to_openai_format(tool)

      assert format.function.parameters.required == ["query"]
      refute "limit" in format.function.parameters.required
      refute "offset" in format.function.parameters.required
    end

    test "handles tool with no required parameters" do
      tool =
        Tool.new(
          :get_time,
          "Gets current time",
          fn _ -> {:ok, DateTime.utc_now()} end,
          parameters: %{
            timezone: [type: :string, required: false]
          }
        )

      format = Tool.to_openai_format(tool)

      assert format.function.parameters.required == []
    end
  end

  describe "Tool.execute/2" do
    test "executes a simple tool successfully" do
      tool =
        Tool.new(
          :add,
          "Adds two numbers",
          fn %{a: a, b: b} -> {:ok, a + b} end
        )

      assert {:ok, 5} = Tool.execute(tool, %{a: 2, b: 3})
    end

    test "executes a tool with string keys" do
      tool =
        Tool.new(
          :greet,
          "Greets a person",
          fn %{name: name} -> {:ok, "Hello, #{name}!"} end
        )

      assert {:ok, "Hello, Alice!"} = Tool.execute(tool, %{"name" => "Alice"})
    end

    test "executes a tool with atom keys" do
      tool =
        Tool.new(
          :greet,
          "Greets a person",
          fn %{name: name} -> {:ok, "Hello, #{name}!"} end
        )

      assert {:ok, "Hello, Bob!"} = Tool.execute(tool, %{name: "Bob"})
    end

    test "handles tool errors" do
      tool =
        Tool.new(
          :divide,
          "Divides numbers",
          fn %{a: a, b: b} ->
            if b == 0 do
              {:error, "Cannot divide by zero"}
            else
              {:ok, a / b}
            end
          end
        )

      assert {:error, "Cannot divide by zero"} = Tool.execute(tool, %{a: 10, b: 0})
    end

    test "handles tool exceptions" do
      tool =
        Tool.new(
          :buggy,
          "A buggy tool",
          fn _ -> raise "Something went wrong" end
        )

      assert {:error, error} = Tool.execute(tool, %{})
      assert error =~ "Something went wrong"
    end

    test "executes context-aware tool" do
      tool =
        Tool.new(
          :get_user_name,
          "Gets current user name",
          fn _params, ctx -> {:ok, ctx.username} end,
          context_aware: true
        )

      context = %{username: "alice", role: "admin"}
      assert {:ok, "alice"} = Tool.execute(tool, %{}, context)
    end

    test "context-aware tool without context returns error" do
      tool =
        Tool.new(
          :get_user,
          "Gets current user",
          fn _params, ctx -> {:ok, ctx} end,
          context_aware: true
        )

      assert {:error, error} = Tool.execute(tool, %{})
      assert error =~ "context-aware"
    end

    test "validates required parameters" do
      tool =
        Tool.new(
          :process,
          "Processes data",
          fn %{data: data} -> {:ok, data} end,
          parameters: %{
            data: [type: :string, required: true]
          }
        )

      assert {:error, error} = Tool.execute(tool, %{})
      assert error =~ "Missing required parameter"
      assert error =~ "data"
    end

    test "validates parameter types - string" do
      tool =
        Tool.new(
          :process,
          "Processes text",
          fn %{text: text} -> {:ok, text} end,
          parameters: %{
            text: [type: :string, required: true]
          }
        )

      assert {:error, error} = Tool.execute(tool, %{text: 123})
      assert error =~ "must be a string"
    end

    test "validates parameter types - number" do
      tool =
        Tool.new(
          :calculate,
          "Calculates value",
          fn %{value: value} -> {:ok, value} end,
          parameters: %{
            value: [type: :number, required: true]
          }
        )

      assert {:ok, 42} = Tool.execute(tool, %{value: 42})
      assert {:ok, 3.14} = Tool.execute(tool, %{value: 3.14})
      assert {:error, error} = Tool.execute(tool, %{value: "not a number"})
      assert error =~ "must be a number"
    end

    test "validates parameter types - integer" do
      tool =
        Tool.new(
          :process,
          "Processes count",
          fn %{count: count} -> {:ok, count} end,
          parameters: %{
            count: [type: :integer, required: true]
          }
        )

      assert {:ok, 42} = Tool.execute(tool, %{count: 42})
      assert {:error, error} = Tool.execute(tool, %{count: 3.14})
      assert error =~ "must be an integer"
    end

    test "validates parameter types - boolean" do
      tool =
        Tool.new(
          :toggle,
          "Toggles setting",
          fn %{enabled: enabled} -> {:ok, enabled} end,
          parameters: %{
            enabled: [type: :boolean, required: true]
          }
        )

      assert {:ok, true} = Tool.execute(tool, %{enabled: true})
      assert {:ok, false} = Tool.execute(tool, %{enabled: false})
      assert {:error, error} = Tool.execute(tool, %{enabled: "yes"})
      assert error =~ "must be a boolean"
    end

    test "validates parameter types - array" do
      tool =
        Tool.new(
          :process,
          "Processes items",
          fn %{items: items} -> {:ok, length(items)} end,
          parameters: %{
            items: [type: :array, required: true]
          }
        )

      assert {:ok, 3} = Tool.execute(tool, %{items: [1, 2, 3]})
      assert {:error, error} = Tool.execute(tool, %{items: "not an array"})
      assert error =~ "must be an array"
    end

    test "validates parameter types - object" do
      tool =
        Tool.new(
          :process,
          "Processes data",
          fn %{data: data} -> {:ok, data} end,
          parameters: %{
            data: [type: :object, required: true]
          }
        )

      assert {:ok, %{key: "value"}} = Tool.execute(tool, %{data: %{key: "value"}})
      assert {:error, error} = Tool.execute(tool, %{data: "not an object"})
      assert error =~ "must be an object"
    end

    test "validates enum values" do
      tool =
        Tool.new(
          :set_mode,
          "Sets mode",
          fn %{mode: mode} -> {:ok, mode} end,
          parameters: %{
            mode: [type: :string, required: true, enum: ["fast", "slow"]]
          }
        )

      assert {:ok, "fast"} = Tool.execute(tool, %{mode: "fast"})
      assert {:error, error} = Tool.execute(tool, %{mode: "invalid"})
      assert error =~ "must be one of"
      assert error =~ "fast"
      assert error =~ "slow"
    end

    test "allows optional parameters to be omitted" do
      tool =
        Tool.new(
          :greet,
          "Greets a person",
          fn params ->
            name = Map.get(params, :name, "stranger")
            {:ok, "Hello, #{name}!"}
          end,
          parameters: %{
            name: [type: :string, required: false]
          }
        )

      assert {:ok, "Hello, stranger!"} = Tool.execute(tool, %{})
      assert {:ok, "Hello, Alice!"} = Tool.execute(tool, %{name: "Alice"})
    end
  end

  describe "Tool parameter validation edge cases" do
    test "validates nested object properties" do
      tool =
        Tool.new(
          :create_user,
          "Creates a user",
          fn %{user: user} -> {:ok, user} end,
          parameters: %{
            user: [
              type: :object,
              required: true,
              properties: %{
                name: %{type: :string},
                age: %{type: :integer}
              }
            ]
          }
        )

      # Valid nested object
      assert {:ok, _} =
               Tool.execute(tool, %{user: %{name: "Alice", age: 30}})
    end

    test "validates array item types" do
      tool =
        Tool.new(
          :process,
          "Processes numbers",
          fn %{numbers: numbers} -> {:ok, Enum.sum(numbers)} end,
          parameters: %{
            numbers: [
              type: :array,
              required: true,
              items: %{type: :integer}
            ]
          }
        )

      # Valid array
      assert {:ok, 6} = Tool.execute(tool, %{numbers: [1, 2, 3]})
    end

    test "handles empty arrays" do
      tool =
        Tool.new(
          :count,
          "Counts items",
          fn %{items: items} -> {:ok, length(items)} end,
          parameters: %{
            items: [type: :array, required: true]
          }
        )

      assert {:ok, 0} = Tool.execute(tool, %{items: []})
    end

    test "handles empty objects" do
      tool =
        Tool.new(
          :process,
          "Processes data",
          fn %{data: data} -> {:ok, map_size(data)} end,
          parameters: %{
            data: [type: :object, required: true]
          }
        )

      assert {:ok, 0} = Tool.execute(tool, %{data: %{}})
    end
  end

  describe "Tool.validate_arguments/2" do
    test "validates all required parameters are present" do
      params = %{
        name: [type: :string, required: true],
        age: [type: :integer, required: true]
      }

      assert :ok = Tool.validate_arguments(%{name: "Alice", age: 30}, params)

      assert {:error, error} = Tool.validate_arguments(%{name: "Alice"}, params)
      assert error =~ "age"
    end

    test "allows optional parameters to be missing" do
      params = %{
        name: [type: :string, required: true],
        email: [type: :string, required: false]
      }

      assert :ok = Tool.validate_arguments(%{name: "Alice"}, params)
      assert :ok = Tool.validate_arguments(%{name: "Alice", email: "alice@example.com"}, params)
    end

    test "validates type correctness" do
      params = %{
        count: [type: :integer, required: true]
      }

      assert :ok = Tool.validate_arguments(%{count: 42}, params)
      assert {:error, _} = Tool.validate_arguments(%{count: "42"}, params)
    end

    test "validates enum constraints" do
      params = %{
        status: [type: :string, required: true, enum: ["active", "inactive"]]
      }

      assert :ok = Tool.validate_arguments(%{status: "active"}, params)
      assert {:error, _} = Tool.validate_arguments(%{status: "pending"}, params)
    end

    test "accepts empty parameters" do
      assert :ok = Tool.validate_arguments(%{}, %{})
    end
  end
end
