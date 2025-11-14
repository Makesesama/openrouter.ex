defmodule Openrouter.Integration.ToolCallingTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag :tool_calling

  setup do
    unless System.get_env("OPENROUTER_API_KEY") || System.get_env("REQORD_MODE") == "replay" do
      ExUnit.configure(exclude: [:integration])
    end

    :ok
  end

  describe "simple tool calling" do
    @tag :integration
    test "calls a single tool and returns result" do
      calculator_tool =
        Openrouter.Tool.new(
          :add,
          "Add two numbers together",
          fn %{a: a, b: b} -> {:ok, a + b} end,
          parameters: %{
            a: [type: :number, required: true, description: "First number"],
            b: [type: :number, required: true, description: "Second number"]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "What is 15 plus 27?",
          model: "openai/gpt-3.5-turbo",
          tools: [calculator_tool]
        )

      assert is_binary(response.content)
      # Response should mention the result (42)
      assert response.content =~ ~r/42/
    end

    @tag :integration
    test "calls tool multiple times in sequence" do
      calculator_tool =
        Openrouter.Tool.new(
          :calculator,
          "Perform arithmetic operations",
          fn %{operation: op, a: a, b: b} ->
            result =
              case op do
                "add" -> a + b
                "multiply" -> a * b
                "subtract" -> a - b
                "divide" when b != 0 -> a / b
              end

            {:ok, result}
          end,
          parameters: %{
            operation: [
              type: :string,
              required: true,
              enum: ["add", "multiply", "subtract", "divide"]
            ],
            a: [type: :number, required: true],
            b: [type: :number, required: true]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Calculate (10 + 5) * 3",
          model: "openai/gpt-3.5-turbo",
          tools: [calculator_tool]
        )

      assert is_binary(response.content)
      # Result should be 45
      assert response.content =~ ~r/45/
    end

    @tag :integration
    test "handles tool returning error" do
      divide_tool =
        Openrouter.Tool.new(
          :divide,
          "Divide two numbers",
          fn %{a: a, b: b} ->
            if b == 0 do
              {:error, "Cannot divide by zero"}
            else
              {:ok, a / b}
            end
          end,
          parameters: %{
            a: [type: :number, required: true],
            b: [type: :number, required: true]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "What is 10 divided by 0?",
          model: "openai/gpt-3.5-turbo",
          tools: [divide_tool]
        )

      # Should handle the error gracefully
      assert is_binary(response.content)
      assert response.content =~ ~r/cannot|error|zero/i
    end
  end

  describe "multiple tools" do
    @tag :integration
    test "chooses correct tool from multiple options" do
      weather_tool =
        Openrouter.Tool.new(
          :get_weather,
          "Get current weather for a location",
          fn %{location: location} ->
            {:ok,
             %{
               location: location,
               temperature: 72,
               condition: "sunny"
             }}
          end,
          parameters: %{
            location: [type: :string, required: true]
          }
        )

      time_tool =
        Openrouter.Tool.new(
          :get_time,
          "Get current time for a timezone",
          fn %{timezone: _tz} ->
            {:ok, "2024-01-15 14:30:00"}
          end,
          parameters: %{
            timezone: [type: :string, required: true]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "What's the weather in Paris?",
          model: "openai/gpt-3.5-turbo",
          tools: [weather_tool, time_tool]
        )

      # Should use weather tool, not time tool
      assert is_binary(response.content)
      assert response.content =~ ~r/weather|temperature|sunny/i
    end

    @tag :integration
    test "uses multiple tools together" do
      search_tool =
        Openrouter.Tool.new(
          :search_products,
          "Search for products",
          fn %{query: query} ->
            products =
              if String.contains?(query, "laptop") do
                [%{id: 1, name: "Laptop Pro", price: 1299.99}]
              else
                []
              end

            {:ok, products}
          end,
          parameters: %{
            query: [type: :string, required: true]
          }
        )

      discount_tool =
        Openrouter.Tool.new(
          :calculate_discount,
          "Calculate discounted price",
          fn %{price: price, percent: percent} ->
            discounted = price * (1 - percent / 100)
            {:ok, Float.round(discounted, 2)}
          end,
          parameters: %{
            price: [type: :number, required: true],
            percent: [type: :number, required: true]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Find laptops and calculate the price with 10% discount",
          model: "openai/gpt-3.5-turbo",
          tools: [search_tool, discount_tool]
        )

      assert is_binary(response.content)
      # Should mention the discounted price (around 1170)
      assert response.content =~ ~r/\d+/
    end
  end

  describe "tool execution callbacks" do
    @tag :integration
    test "on_tool_call callback is invoked" do
      tool =
        Openrouter.Tool.new(
          :test_tool,
          "A test tool",
          fn _ -> {:ok, "result"} end,
          parameters: %{}
        )

      test_pid = self()

      {:ok, _response} =
        Openrouter.Agent.run(
          "Use the test tool",
          model: "openai/gpt-3.5-turbo",
          tools: [tool],
          on_tool_call: fn tool_call ->
            send(test_pid, {:tool_called, tool_call.function.name})
          end
        )

      assert_receive {:tool_called, "test_tool"}, 5000
    end

    @tag :integration
    test "on_tool_result callback is invoked" do
      tool =
        Openrouter.Tool.new(
          :echo,
          "Echo a message",
          fn %{message: msg} -> {:ok, msg} end,
          parameters: %{
            message: [type: :string, required: true]
          }
        )

      test_pid = self()

      {:ok, _response} =
        Openrouter.Agent.run(
          "Echo the message 'hello'",
          model: "openai/gpt-3.5-turbo",
          tools: [tool],
          on_tool_result: fn _tool_call, result ->
            send(test_pid, {:tool_result, result})
          end
        )

      assert_receive {:tool_result, _result}, 5000
    end

    @tag :integration
    test "both callbacks are invoked in sequence" do
      tool =
        Openrouter.Tool.new(
          :counter,
          "Count items",
          fn %{items: items} -> {:ok, length(items)} end,
          parameters: %{
            items: [type: :array, required: true]
          }
        )

      test_pid = self()

      {:ok, _response} =
        Openrouter.Agent.run(
          "Count these items: apple, banana, cherry",
          model: "openai/gpt-3.5-turbo",
          tools: [tool],
          on_tool_call: fn tool_call ->
            send(test_pid, {:called, tool_call.function.name})
          end,
          on_tool_result: fn _tool_call, result ->
            send(test_pid, {:result, result})
          end
        )

      # Should receive both messages in order
      assert_receive {:called, "counter"}, 5000
      assert_receive {:result, _}, 5000
    end
  end

  describe "max_iterations" do
    @tag :integration
    test "respects max_iterations limit" do
      increment_tool =
        Openrouter.Tool.new(
          :increment,
          "Increment a number",
          fn %{value: value} -> {:ok, value + 1} end,
          parameters: %{
            value: [type: :integer, required: true]
          }
        )

      result =
        Openrouter.Agent.run(
          "Keep incrementing from 0 until you reach 100",
          model: "openai/gpt-3.5-turbo",
          tools: [increment_tool],
          max_iterations: 2
        )

      # Should hit the iteration limit
      assert {:error, error} = result
      assert error =~ ~r/maximum iterations/i
    end

    @tag :integration
    test "completes within max_iterations" do
      simple_tool =
        Openrouter.Tool.new(
          :get_answer,
          "Get the answer",
          fn _ -> {:ok, 42} end,
          parameters: %{}
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "What is the answer?",
          model: "openai/gpt-3.5-turbo",
          tools: [simple_tool],
          max_iterations: 5
        )

      assert is_binary(response.content)
      assert response.content =~ ~r/42/
    end

    @tag :integration
    test "custom max_iterations higher than default" do
      counter_tool =
        Openrouter.Tool.new(
          :count,
          "Count up",
          fn %{current: current} -> {:ok, current + 1} end,
          parameters: %{
            current: [type: :integer, required: true]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Count from 1 to 3",
          model: "openai/gpt-3.5-turbo",
          tools: [counter_tool],
          max_iterations: 10
        )

      assert is_binary(response.content)
    end
  end

  describe "tool parameter types" do
    @tag :integration
    test "handles string parameters" do
      greet_tool =
        Openrouter.Tool.new(
          :greet,
          "Greet a person by name",
          fn %{name: name} -> {:ok, "Hello, #{name}!"} end,
          parameters: %{
            name: [type: :string, required: true]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Greet Alice",
          model: "openai/gpt-3.5-turbo",
          tools: [greet_tool]
        )

      assert response.content =~ ~r/Alice/i
    end

    @tag :integration
    test "handles number parameters" do
      power_tool =
        Openrouter.Tool.new(
          :power,
          "Calculate x to the power of y",
          fn %{base: base, exponent: exp} ->
            {:ok, :math.pow(base, exp)}
          end,
          parameters: %{
            base: [type: :number, required: true],
            exponent: [type: :number, required: true]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "What is 2 to the power of 8?",
          model: "openai/gpt-3.5-turbo",
          tools: [power_tool]
        )

      # 2^8 = 256
      assert response.content =~ ~r/256/
    end

    @tag :integration
    test "handles boolean parameters" do
      toggle_tool =
        Openrouter.Tool.new(
          :set_feature,
          "Enable or disable a feature",
          fn %{feature: feature, enabled: enabled} ->
            status = if enabled, do: "enabled", else: "disabled"
            {:ok, "Feature '#{feature}' is now #{status}"}
          end,
          parameters: %{
            feature: [type: :string, required: true],
            enabled: [type: :boolean, required: true]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Enable the dark mode feature",
          model: "openai/gpt-3.5-turbo",
          tools: [toggle_tool]
        )

      assert response.content =~ ~r/enabled|dark mode/i
    end

    @tag :integration
    test "handles array parameters" do
      sum_tool =
        Openrouter.Tool.new(
          :sum_numbers,
          "Calculate sum of numbers",
          fn %{numbers: numbers} ->
            {:ok, Enum.sum(numbers)}
          end,
          parameters: %{
            numbers: [
              type: :array,
              required: true,
              description: "List of numbers to sum",
              items: %{type: :number}
            ]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Sum these numbers: 10, 20, 30, 40",
          model: "openai/gpt-3.5-turbo",
          tools: [sum_tool]
        )

      # Sum should be 100
      assert response.content =~ ~r/100/
    end

    @tag :integration
    test "handles object parameters" do
      create_user_tool =
        Openrouter.Tool.new(
          :create_user,
          "Create a new user",
          fn %{user: user} ->
            {:ok, "User #{user["name"]} (#{user["email"]}) created"}
          end,
          parameters: %{
            user: [
              type: :object,
              required: true,
              properties: %{
                name: %{type: :string},
                email: %{type: :string}
              }
            ]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Create a user with name 'Alice' and email 'alice@example.com'",
          model: "openai/gpt-3.5-turbo",
          tools: [create_user_tool]
        )

      assert response.content =~ ~r/Alice|alice@example.com/i
    end

    @tag :integration
    test "handles enum parameters" do
      status_tool =
        Openrouter.Tool.new(
          :set_status,
          "Set user status",
          fn %{status: status} ->
            {:ok, "Status set to: #{status}"}
          end,
          parameters: %{
            status: [
              type: :string,
              required: true,
              enum: ["online", "away", "busy", "offline"]
            ]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Set my status to busy",
          model: "openai/gpt-3.5-turbo",
          tools: [status_tool]
        )

      assert response.content =~ ~r/busy/i
    end
  end

  describe "conversation with history" do
    @tag :integration
    test "maintains context across multiple turns" do
      # Create a stateful storage for the conversation
      {:ok, agent} = Agent.start_link(fn -> %{} end)

      store_tool =
        Openrouter.Tool.new(
          :store_value,
          "Store a key-value pair",
          fn %{key: key, value: value} ->
            Agent.update(agent, fn state ->
              Map.put(state, key, value)
            end)

            {:ok, "Stored #{key} = #{value}"}
          end,
          parameters: %{
            key: [type: :string, required: true],
            value: [type: :string, required: true]
          }
        )

      retrieve_tool =
        Openrouter.Tool.new(
          :retrieve_value,
          "Retrieve a stored value by key",
          fn %{key: key} ->
            value = Agent.get(agent, fn state -> Map.get(state, key) end)

            if value do
              {:ok, value}
            else
              {:error, "Key not found"}
            end
          end,
          parameters: %{
            key: [type: :string, required: true]
          }
        )

      # First turn: store a value
      {:ok, response1} =
        Openrouter.Agent.run(
          "Store the value 'secret123' with key 'password'",
          model: "openai/gpt-3.5-turbo",
          tools: [store_tool, retrieve_tool]
        )

      assert response1.content =~ ~r/stored/i

      # Second turn: retrieve the value
      messages = [
        %{role: :user, content: "Store the value 'secret123' with key 'password'"},
        %{role: :assistant, content: response1.content},
        %{role: :user, content: "What's the password I just stored?"}
      ]

      {:ok, response2} =
        Openrouter.Agent.run_with_history(
          messages,
          model: "openai/gpt-3.5-turbo",
          tools: [store_tool, retrieve_tool]
        )

      assert response2.content =~ ~r/secret123/i
    end

    @tag :integration
    test "run_with_history works with system message" do
      tool =
        Openrouter.Tool.new(
          :add,
          "Add two numbers",
          fn %{a: a, b: b} -> {:ok, a + b} end,
          parameters: %{
            a: [type: :number, required: true],
            b: [type: :number, required: true]
          }
        )

      messages = [
        %{role: :system, content: "You are a helpful math assistant"},
        %{role: :user, content: "What is 5 plus 3?"}
      ]

      {:ok, response} =
        Openrouter.Agent.run_with_history(
          messages,
          model: "openai/gpt-3.5-turbo",
          tools: [tool]
        )

      assert is_binary(response.content)
      assert response.content =~ ~r/8/
    end
  end

  describe "complex real-world scenarios" do
    @tag :integration
    test "multi-step workflow with data transformation" do
      fetch_data_tool =
        Openrouter.Tool.new(
          :fetch_user_data,
          "Fetch user data by ID",
          fn %{user_id: id} ->
            {:ok,
             %{
               id: id,
               name: "User #{id}",
               orders: [1, 2, 3]
             }}
          end,
          parameters: %{
            user_id: [type: :integer, required: true]
          }
        )

      count_orders_tool =
        Openrouter.Tool.new(
          :count_orders,
          "Count number of orders",
          fn %{order_ids: ids} ->
            {:ok, length(ids)}
          end,
          parameters: %{
            order_ids: [type: :array, required: true, items: %{type: :integer}]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Fetch data for user 123 and count their orders",
          model: "openai/gpt-3.5-turbo",
          tools: [fetch_data_tool, count_orders_tool]
        )

      # Should mention 3 orders
      assert response.content =~ ~r/3|three/i
    end

    @tag :integration
    test "conditional tool execution based on previous results" do
      check_stock_tool =
        Openrouter.Tool.new(
          :check_stock,
          "Check if product is in stock",
          fn %{product_id: id} ->
            in_stock = rem(id, 2) == 0
            {:ok, %{product_id: id, in_stock: in_stock}}
          end,
          parameters: %{
            product_id: [type: :integer, required: true]
          }
        )

      order_product_tool =
        Openrouter.Tool.new(
          :order_product,
          "Order a product",
          fn %{product_id: id} ->
            {:ok, "Order placed for product #{id}"}
          end,
          parameters: %{
            product_id: [type: :integer, required: true]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Check if product 4 is in stock, and if it is, order it",
          model: "openai/gpt-3.5-turbo",
          tools: [check_stock_tool, order_product_tool]
        )

      # Product 4 (even) should be in stock, so order should be placed
      assert response.content =~ ~r/order|placed/i
    end
  end

  describe "error handling" do
    @tag :integration
    test "handles tool not found gracefully" do
      # Agent with no tools
      result =
        Openrouter.Agent.run(
          "Use the calculator tool",
          model: "openai/gpt-3.5-turbo",
          tools: []
        )

      # Should complete without error (no tools to call)
      assert {:ok, response} = result
      assert is_binary(response.content)
    end

    @tag :integration
    test "handles malformed tool responses" do
      buggy_tool =
        Openrouter.Tool.new(
          :buggy,
          "A tool that might fail",
          fn %{action: action} ->
            case action do
              "succeed" -> {:ok, "Success"}
              "fail" -> {:error, "Operation failed"}
              _ -> raise "Unexpected error"
            end
          end,
          parameters: %{
            action: [type: :string, required: true]
          }
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Try the buggy tool with action 'fail'",
          model: "openai/gpt-3.5-turbo",
          tools: [buggy_tool]
        )

      # Should handle the error and continue
      assert is_binary(response.content)
    end

    @tag :integration
    test "handles network errors gracefully" do
      # Test with invalid model (should error)
      tool =
        Openrouter.Tool.new(
          :test,
          "Test tool",
          fn _ -> {:ok, "result"} end,
          parameters: %{}
        )

      result =
        Openrouter.Agent.run(
          "Use the test tool",
          model: "invalid/model/name",
          tools: [tool]
        )

      # Should return an error
      assert {:error, _error} = result
    end
  end

  describe "agent without tools" do
    @tag :integration
    test "works as normal chat when no tools provided" do
      {:ok, response} =
        Openrouter.Agent.run(
          "What is 2 + 2?",
          model: "openai/gpt-3.5-turbo",
          tools: []
        )

      assert is_binary(response.content)
      assert response.content =~ ~r/4|four/i
    end

    @tag :integration
    test "includes system message when no tools" do
      {:ok, response} =
        Openrouter.Agent.run(
          "Say hello",
          model: "openai/gpt-3.5-turbo",
          tools: [],
          system: "You are a friendly assistant. Always be enthusiastic."
        )

      assert is_binary(response.content)
      assert response.content =~ ~r/hello|hi/i
    end
  end
end
