#!/usr/bin/env elixir
#
# Tool Calling Examples
#
# This file demonstrates how to use OpenRouter's tool/function calling
# capabilities to build agentic workflows.
#
# Run with: mix run examples/tool_calling.exs

Mix.install([{:openrouter, path: "."}])

require Logger

IO.puts("\n=== Tool Calling Examples ===\n")

# ============================================================================
# Example 1: Simple Calculator Tool
# ============================================================================

IO.puts("1. Simple Calculator Tool")
IO.puts("   Using a basic tool to perform calculations\n")

calculator_tool =
  Openrouter.Tool.new(
    :calculator,
    "Perform basic arithmetic operations (add, subtract, multiply, divide)",
    fn %{operation: op, a: a, b: b} ->
      result =
        case op do
          "add" -> a + b
          "subtract" -> a - b
          "multiply" -> a * b
          "divide" when b != 0 -> a / b
          "divide" -> {:error, "Cannot divide by zero"}
          _ -> {:error, "Unknown operation: #{op}"}
        end

      {:ok, result}
    end,
    parameters: %{
      operation: [type: :string, required: true, enum: ["add", "subtract", "multiply", "divide"]],
      a: [type: :number, required: true, description: "First number"],
      b: [type: :number, required: true, description: "Second number"]
    }
  )

{:ok, response} =
  Openrouter.Agent.run(
    "What is 25 multiplied by 4, and then add 10 to the result?",
    model: "openai/gpt-3.5-turbo",
    tools: [calculator_tool]
  )

IO.puts("Result: #{response.content}\n")

# ============================================================================
# Example 2: Multiple Tools Working Together
# ============================================================================

IO.puts("2. Multiple Tools Working Together")
IO.puts("   Agent uses multiple tools to solve a complex task\n")

weather_tool =
  Openrouter.Tool.new(
    :get_weather,
    "Get current weather for a location",
    fn %{location: location} ->
      # Simulated weather data
      weather = %{
        location: location,
        temperature: Enum.random(60..85),
        condition: Enum.random(["sunny", "cloudy", "rainy"]),
        humidity: Enum.random(30..80)
      }

      {:ok, weather}
    end,
    parameters: %{
      location: [type: :string, required: true, description: "City name or location"]
    }
  )

unit_converter_tool =
  Openrouter.Tool.new(
    :convert_temperature,
    "Convert temperature between Fahrenheit and Celsius",
    fn %{value: value, from: from, to: to} ->
      result =
        case {from, to} do
          {"fahrenheit", "celsius"} -> (value - 32) * 5 / 9
          {"celsius", "fahrenheit"} -> value * 9 / 5 + 32
          _ -> value
        end

      {:ok, %{value: Float.round(result, 1), unit: to}}
    end,
    parameters: %{
      value: [type: :number, required: true],
      from: [type: :string, required: true, enum: ["fahrenheit", "celsius"]],
      to: [type: :string, required: true, enum: ["fahrenheit", "celsius"]]
    }
  )

{:ok, response} =
  Openrouter.Agent.run(
    "What's the weather in Paris? Also convert the temperature to Celsius.",
    model: "openai/gpt-3.5-turbo",
    tools: [weather_tool, unit_converter_tool]
  )

IO.puts("Result: #{response.content}\n")

# ============================================================================
# Example 3: Tool Execution Callbacks
# ============================================================================

IO.puts("3. Tool Execution Callbacks")
IO.puts("   Monitor tool execution with callbacks\n")

database_tool =
  Openrouter.Tool.new(
    :query_database,
    "Query the user database",
    fn %{query: query} ->
      # Simulated database query
      :timer.sleep(500) # Simulate query time

      results =
        case query do
          "count_users" -> %{count: 1234}
          "recent_signups" -> %{users: ["alice@example.com", "bob@example.com"]}
          _ -> %{error: "Unknown query"}
        end

      {:ok, results}
    end,
    parameters: %{
      query: [type: :string, required: true, description: "Query type"]
    }
  )

{:ok, response} =
  Openrouter.Agent.run(
    "How many users are in the database? Also show me recent signups.",
    model: "openai/gpt-3.5-turbo",
    tools: [database_tool],
    on_tool_call: fn tool_call ->
      IO.puts("   → Calling tool: #{tool_call.function.name}")
      IO.puts("   → Arguments: #{tool_call.function.arguments}")
    end,
    on_tool_result: fn tool_call, result ->
      IO.puts("   → Tool #{tool_call.function.name} completed")
      IO.puts("   → Result: #{inspect(result)}")
    end
  )

IO.puts("\nFinal Result: #{response.content}\n")

# ============================================================================
# Example 4: Context-Aware Tools
# ============================================================================

IO.puts("4. Context-Aware Tools")
IO.puts("   Tools that access external context/dependencies\n")

# Simulated user session
user_context = %{
  user_id: "user_123",
  username: "alice",
  role: "admin",
  email: "alice@example.com"
}

get_user_info_tool =
  Openrouter.Tool.new(
    :get_user_info,
    "Get information about the current user",
    fn %{field: field}, ctx ->
      # Context-aware tool receives the context as second argument
      value = Map.get(ctx, String.to_atom(field), "unknown")
      {:ok, %{field: field, value: value}}
    end,
    parameters: %{
      field: [
        type: :string,
        required: true,
        enum: ["user_id", "username", "role", "email"],
        description: "User field to retrieve"
      ]
    },
    context_aware: true
  )

check_permission_tool =
  Openrouter.Tool.new(
    :check_permission,
    "Check if current user has a specific permission",
    fn %{action: action}, ctx ->
      # Admin users have all permissions
      has_permission = ctx.role == "admin"
      {:ok, %{action: action, allowed: has_permission}}
    end,
    parameters: %{
      action: [type: :string, required: true, description: "Action to check permission for"]
    },
    context_aware: true
  )

# Note: Context-aware tools would require Agent.run to accept a context parameter
# This is a demonstration of the tool definition pattern

IO.puts("Context-aware tools created:")
IO.puts("  - get_user_info (context_aware: #{get_user_info_tool.context_aware})")
IO.puts("  - check_permission (context_aware: #{check_permission_tool.context_aware})")
IO.puts("  Context: #{inspect(user_context)}\n")

# ============================================================================
# Example 5: Error Handling in Tools
# ============================================================================

IO.puts("5. Error Handling in Tools")
IO.puts("   Tools that handle errors gracefully\n")

risky_tool =
  Openrouter.Tool.new(
    :risky_operation,
    "Perform an operation that might fail",
    fn %{action: action} ->
      case action do
        "safe" ->
          {:ok, "Operation completed successfully"}

        "risky" ->
          if :rand.uniform() > 0.5 do
            {:ok, "Risky operation succeeded!"}
          else
            {:error, "Operation failed: Random failure occurred"}
          end

        "invalid" ->
          {:error, "Invalid action requested"}

        _ ->
          {:error, "Unknown action: #{action}"}
      end
    end,
    parameters: %{
      action: [type: :string, required: true, description: "Action to perform"]
    }
  )

{:ok, response} =
  Openrouter.Agent.run(
    "Try to perform a risky operation, and if it fails, try a safe one instead.",
    model: "openai/gpt-3.5-turbo",
    tools: [risky_tool],
    on_tool_result: fn _tool_call, result ->
      case result do
        {:ok, _} -> IO.puts("   ✓ Tool succeeded")
        {:error, msg} -> IO.puts("   ✗ Tool failed: #{msg}")
      end
    end
  )

IO.puts("\nResult: #{response.content}\n")

# ============================================================================
# Example 6: Max Iterations Safety
# ============================================================================

IO.puts("6. Max Iterations Safety")
IO.puts("   Preventing infinite loops with max_iterations\n")

increment_tool =
  Openrouter.Tool.new(
    :increment,
    "Increment a counter",
    fn %{value: value} ->
      {:ok, value + 1}
    end,
    parameters: %{
      value: [type: :integer, required: true]
    }
  )

# This will hit the max_iterations limit
result =
  Openrouter.Agent.run(
    "Keep incrementing from 0 until you reach 100",
    model: "openai/gpt-3.5-turbo",
    tools: [increment_tool],
    max_iterations: 3 # Low limit to demonstrate the safety
  )

case result do
  {:ok, response} ->
    IO.puts("Completed: #{response.content}")

  {:error, error} ->
    IO.puts("Hit safety limit: #{error}")
end

IO.puts("")

# ============================================================================
# Example 7: Complex Multi-Tool Workflow
# ============================================================================

IO.puts("7. Complex Multi-Tool Workflow")
IO.puts("   Combining multiple tools to solve a real-world problem\n")

search_products_tool =
  Openrouter.Tool.new(
    :search_products,
    "Search for products in the catalog",
    fn %{query: query, category: category} ->
      # Simulated product search
      products = [
        %{id: 1, name: "Laptop Pro", price: 1299.99, category: "electronics"},
        %{id: 2, name: "Wireless Mouse", price: 29.99, category: "electronics"},
        %{id: 3, name: "Office Chair", price: 249.99, category: "furniture"},
        %{id: 4, name: "Desk Lamp", price: 39.99, category: "furniture"}
      ]

      filtered =
        products
        |> Enum.filter(fn p ->
          (category == nil or p.category == category) and
            String.contains?(String.downcase(p.name), String.downcase(query))
        end)

      {:ok, filtered}
    end,
    parameters: %{
      query: [type: :string, required: true, description: "Search query"],
      category: [
        type: :string,
        required: false,
        description: "Filter by category",
        enum: ["electronics", "furniture"]
      ]
    }
  )

calculate_discount_tool =
  Openrouter.Tool.new(
    :calculate_discount,
    "Calculate discounted price",
    fn %{price: price, discount_percent: discount} ->
      discounted = price * (1 - discount / 100)
      savings = price - discounted

      {:ok, %{
        original_price: price,
        discount_percent: discount,
        discounted_price: Float.round(discounted, 2),
        savings: Float.round(savings, 2)
      }}
    end,
    parameters: %{
      price: [type: :number, required: true],
      discount_percent: [type: :number, required: true, description: "Discount percentage (0-100)"]
    }
  )

check_inventory_tool =
  Openrouter.Tool.new(
    :check_inventory,
    "Check if product is in stock",
    fn %{product_id: id} ->
      # Simulated inventory check
      in_stock = rem(id, 2) == 0
      quantity = if in_stock, do: Enum.random(5..50), else: 0

      {:ok, %{product_id: id, in_stock: in_stock, quantity: quantity}}
    end,
    parameters: %{
      product_id: [type: :integer, required: true]
    }
  )

{:ok, response} =
  Openrouter.Agent.run(
    """
    I'm looking for a laptop in the electronics category.
    Can you find one, check if it's in stock, and calculate the price with a 15% discount?
    """,
    model: "openai/gpt-3.5-turbo",
    tools: [search_products_tool, calculate_discount_tool, check_inventory_tool],
    on_tool_call: fn tool_call ->
      IO.puts("   → #{tool_call.function.name}")
    end
  )

IO.puts("\nFinal Answer: #{response.content}\n")

# ============================================================================
# Example 8: Conversation with History
# ============================================================================

IO.puts("8. Conversation with History")
IO.puts("   Multi-turn conversation with tool access\n")

note_storage = Agent.start_link(fn -> %{} end)

save_note_tool =
  Openrouter.Tool.new(
    :save_note,
    "Save a note with a title",
    fn %{title: title, content: content} ->
      Agent.update(note_storage, fn notes ->
        Map.put(notes, title, content)
      end)

      {:ok, "Note '#{title}' saved successfully"}
    end,
    parameters: %{
      title: [type: :string, required: true],
      content: [type: :string, required: true]
    }
  )

get_note_tool =
  Openrouter.Tool.new(
    :get_note,
    "Retrieve a saved note by title",
    fn %{title: title} ->
      note = Agent.get(note_storage, fn notes -> Map.get(notes, title) end)

      if note do
        {:ok, %{title: title, content: note}}
      else
        {:error, "Note '#{title}' not found"}
      end
    end,
    parameters: %{
      title: [type: :string, required: true]
    }
  )

list_notes_tool =
  Openrouter.Tool.new(
    :list_notes,
    "List all saved note titles",
    fn _params ->
      titles = Agent.get(note_storage, fn notes -> Map.keys(notes) end)
      {:ok, %{notes: titles, count: length(titles)}}
    end,
    parameters: %{}
  )

# First turn: Save some notes
{:ok, response1} =
  Openrouter.Agent.run(
    "Save a note titled 'Meeting' with content 'Discuss Q4 planning'",
    model: "openai/gpt-3.5-turbo",
    tools: [save_note_tool, get_note_tool, list_notes_tool]
  )

IO.puts("Turn 1: #{response1.content}")

# Second turn: Save another note (with conversation history)
messages = [
  %{role: :user, content: "Save a note titled 'Meeting' with content 'Discuss Q4 planning'"},
  %{role: :assistant, content: response1.content},
  %{role: :user, content: "Now save another note titled 'TODO' with content 'Review code'"}
]

{:ok, response2} =
  Openrouter.Agent.run_with_history(
    messages,
    model: "openai/gpt-3.5-turbo",
    tools: [save_note_tool, get_note_tool, list_notes_tool]
  )

IO.puts("Turn 2: #{response2.content}")

# Third turn: List all notes
messages =
  messages ++
    [
      %{role: :assistant, content: response2.content},
      %{role: :user, content: "What notes do I have saved?"}
    ]

{:ok, response3} =
  Openrouter.Agent.run_with_history(
    messages,
    model: "openai/gpt-3.5-turbo",
    tools: [save_note_tool, get_note_tool, list_notes_tool]
  )

IO.puts("Turn 3: #{response3.content}\n")

# ============================================================================
# Example 9: Advanced Tool Parameter Types
# ============================================================================

IO.puts("9. Advanced Tool Parameter Types")
IO.puts("   Tools with complex parameter schemas\n")

process_data_tool =
  Openrouter.Tool.new(
    :process_data,
    "Process data with various options",
    fn params ->
      result = %{
        items_processed: length(params[:items] || []),
        options_applied: params[:options] || %{},
        metadata: params[:metadata]
      }

      {:ok, result}
    end,
    parameters: %{
      items: [
        type: :array,
        required: true,
        description: "List of items to process",
        items: %{type: :string}
      ],
      options: [
        type: :object,
        required: false,
        description: "Processing options",
        properties: %{
          format: %{type: :string, enum: ["json", "csv", "xml"]},
          validate: %{type: :boolean},
          timeout: %{type: :integer}
        }
      ],
      metadata: [
        type: :object,
        required: false,
        description: "Additional metadata"
      ]
    }
  )

{:ok, response} =
  Openrouter.Agent.run(
    """
    Process these items: ["apple", "banana", "cherry"]
    Use JSON format with validation enabled and a 30 second timeout.
    """,
    model: "openai/gpt-3.5-turbo",
    tools: [process_data_tool]
  )

IO.puts("Result: #{response.content}\n")

IO.puts("=== All Examples Complete ===\n")
