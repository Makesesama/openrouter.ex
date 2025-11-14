#!/usr/bin/env elixir
#
# RunContext & Dependency Injection Examples
#
# This file demonstrates how to use RunContext for type-safe dependency
# injection in agentic workflows, inspired by Pydantic AI's pattern.
#
# Run with: mix run examples/run_context.exs

Mix.install([{:openrouter, path: "."}])

require Logger

IO.puts("\n=== RunContext & Dependency Injection Examples ===\n")

# ============================================================================
# Example 1: Basic Dependency Injection
# ============================================================================

IO.puts("1. Basic Dependency Injection")
IO.puts("   Passing dependencies to context-aware tools\n")

# Define your application's dependencies
defmodule AppDeps do
  @moduledoc "Application-level dependencies for tools"
  defstruct [:user_id, :api_key, :environment]

  @type t :: %__MODULE__{
          user_id: integer(),
          api_key: String.t(),
          environment: String.t()
        }
end

# Create a context-aware tool
get_user_info_tool =
  Openrouter.Tool.new(
    :get_user_info,
    "Get information about the current user",
    fn ctx, %{field: field} ->
      # ctx is a RunContext struct
      # ctx.deps contains our AppDeps struct
      user_id = ctx.deps.user_id
      environment = ctx.deps.environment

      # Simulate database lookup
      user_data = %{
        user_id: user_id,
        name: "User #{user_id}",
        email: "user#{user_id}@example.com",
        role: "admin",
        environment: environment
      }

      value = Map.get(user_data, String.to_atom(field), "unknown")
      {:ok, %{field: field, value: value}}
    end,
    parameters: %{
      field: [
        type: :string,
        required: true,
        enum: ["user_id", "name", "email", "role", "environment"],
        description: "User field to retrieve"
      ]
    },
    context_aware: true
  )

# Create dependencies
deps = %AppDeps{
  user_id: 123,
  api_key: "secret_key",
  environment: "production"
}

{:ok, response} =
  Openrouter.Agent.run(
    "What is my user ID and email?",
    model: "openai/gpt-3.5-turbo",
    tools: [get_user_info_tool],
    deps: deps
  )

IO.puts("Result: #{response.content}\n")

# ============================================================================
# Example 2: Database Connection Injection
# ============================================================================

IO.puts("2. Database Connection Injection")
IO.puts("   Tools accessing database through injected connection\n")

defmodule DatabaseDeps do
  @moduledoc "Dependencies for database access"
  defstruct [:conn, :customer_id, :tenant_id]

  @type t :: %__MODULE__{
          conn: term(),
          customer_id: integer(),
          tenant_id: integer()
        }
end

# Simulated database operations
defmodule FakeDB do
  def query(_conn, "SELECT * FROM orders WHERE customer_id = ?", [customer_id, _tenant_id]) do
    {:ok, [
      %{id: 1, total: 150.00, status: "completed", customer_id: customer_id},
      %{id: 2, total: 89.99, status: "pending", customer_id: customer_id}
    ]}
  end

  def query(_conn, "SELECT SUM(total) FROM orders WHERE customer_id = ?", [customer_id, _tenant_id, status]) do
    total = if status == "completed", do: 150.00, else: 239.99
    {:ok, total}
  end
end

# Context-aware database query tool
query_orders_tool =
  Openrouter.Tool.new(
    :query_orders,
    "Query customer orders from database",
    fn ctx, _params ->
      # Access injected database connection
      {:ok, orders} = FakeDB.query(
        ctx.deps.conn,
        "SELECT * FROM orders WHERE customer_id = ?",
        [ctx.deps.customer_id, ctx.deps.tenant_id]
      )

      {:ok, orders}
    end,
    parameters: %{},
    context_aware: true
  )

calculate_total_tool =
  Openrouter.Tool.new(
    :calculate_order_total,
    "Calculate total of customer orders",
    fn ctx, %{status: status} ->
      {:ok, total} = FakeDB.query(
        ctx.deps.conn,
        "SELECT SUM(total) FROM orders WHERE customer_id = ?",
        [ctx.deps.customer_id, ctx.deps.tenant_id, status]
      )

      {:ok, %{total: total, status: status}}
    end,
    parameters: %{
      status: [type: :string, required: true, enum: ["completed", "pending", "all"]]
    },
    context_aware: true
  )

# Create database dependencies
db_deps = %DatabaseDeps{
  conn: :fake_conn,
  customer_id: 456,
  tenant_id: 789
}

{:ok, response} =
  Openrouter.Agent.run(
    "Show me my orders and calculate the total of completed ones",
    model: "openai/gpt-3.5-turbo",
    tools: [query_orders_tool, calculate_total_tool],
    deps: db_deps
  )

IO.puts("Result: #{response.content}\n")

# ============================================================================
# Example 3: Multi-Service Dependencies
# ============================================================================

IO.puts("3. Multi-Service Dependencies")
IO.puts("   Tools accessing multiple services through dependencies\n")

defmodule ServiceDeps do
  @moduledoc "Dependencies for multiple services"
  defstruct [:http_client, :cache, :logger, :user_context]

  @type t :: %__MODULE__{
          http_client: term(),
          cache: term(),
          logger: term(),
          user_context: map()
        }
end

# Simulated external API
defmodule FakeAPI do
  def fetch_weather(_http_client, location) do
    {:ok, %{location: location, temp: 72, condition: "sunny"}}
  end

  def fetch_news(_http_client, category) do
    {:ok, [
      %{title: "Breaking News in #{category}", date: "2024-01-15"},
      %{title: "Latest Update on #{category}", date: "2024-01-15"}
    ]}
  end
end

# Simulated cache
defmodule FakeCache do
  def get(_cache, _key), do: nil

  def put(_cache, _key, _value, _opts), do: :ok
end

weather_tool =
  Openrouter.Tool.new(
    :get_weather,
    "Get weather for a location",
    fn ctx, %{location: location} ->
      # Try cache first
      cache_key = "weather:#{location}"

      case FakeCache.get(ctx.deps.cache, cache_key) do
        nil ->
          # Cache miss - fetch from API
          {:ok, weather} = FakeAPI.fetch_weather(ctx.deps.http_client, location)

          # Store in cache
          FakeCache.put(ctx.deps.cache, cache_key, weather, ttl: 300)

          # Log access
          if ctx.deps.logger do
            IO.puts("   [LOG] User #{ctx.deps.user_context.user_id} fetched weather for #{location}")
          end

          {:ok, weather}

        cached_weather ->
          {:ok, cached_weather}
      end
    end,
    parameters: %{
      location: [type: :string, required: true]
    },
    context_aware: true
  )

news_tool =
  Openrouter.Tool.new(
    :get_news,
    "Get latest news by category",
    fn ctx, %{category: category} ->
      {:ok, news} = FakeAPI.fetch_news(ctx.deps.http_client, category)

      if ctx.deps.logger do
        IO.puts("   [LOG] User #{ctx.deps.user_context.user_id} fetched news for #{category}")
      end

      {:ok, news}
    end,
    parameters: %{
      category: [type: :string, required: true]
    },
    context_aware: true
  )

# Create service dependencies
service_deps = %ServiceDeps{
  http_client: :fake_http,
  cache: :fake_cache,
  logger: true,
  user_context: %{user_id: 789, name: "Alice"}
}

{:ok, response} =
  Openrouter.Agent.run(
    "What's the weather in Seattle and get me tech news?",
    model: "openai/gpt-3.5-turbo",
    tools: [weather_tool, news_tool],
    deps: service_deps
  )

IO.puts("\nResult: #{response.content}\n")

# ============================================================================
# Example 4: RunContext Inspection
# ============================================================================

IO.puts("4. RunContext Inspection")
IO.puts("   Tools that inspect RunContext metadata\n")

inspect_context_tool =
  Openrouter.Tool.new(
    :inspect_context,
    "Inspect the current RunContext",
    fn ctx, _params ->
      info = %{
        model: ctx.model,
        message_count: Openrouter.RunContext.message_count(ctx),
        has_deps: Openrouter.RunContext.has_deps?(ctx),
        retry_count: ctx.retry_count,
        usage: if(ctx.usage, do: Map.from_struct(ctx.usage), else: nil)
      }

      {:ok, info}
    end,
    parameters: %{},
    context_aware: true
  )

simple_deps = %{session_id: "abc123"}

{:ok, response} =
  Openrouter.Agent.run(
    "Inspect the current context",
    model: "openai/gpt-3.5-turbo",
    tools: [inspect_context_tool],
    deps: simple_deps
  )

IO.puts("Result: #{response.content}\n")

# ============================================================================
# Example 5: RunContext with Conversation History
# ============================================================================

IO.puts("5. RunContext with Conversation History")
IO.puts("   Using RunContext across multiple turns\n")

defmodule ConversationDeps do
  defstruct [:user_id, :preferences, :history_store]

  @type t :: %__MODULE__{
          user_id: integer(),
          preferences: map(),
          history_store: term()
        }
end

save_preference_tool =
  Openrouter.Tool.new(
    :save_preference,
    "Save a user preference",
    fn ctx, %{key: key, value: value} ->
      # In real app, would save to database
      IO.puts("   [SAVE] User #{ctx.deps.user_id}: #{key} = #{value}")

      {:ok, "Preference '#{key}' saved as '#{value}'"}
    end,
    parameters: %{
      key: [type: :string, required: true],
      value: [type: :string, required: true]
    },
    context_aware: true
  )

get_preference_tool =
  Openrouter.Tool.new(
    :get_preference,
    "Get a saved user preference",
    fn ctx, %{key: key} ->
      # Simulate retrieval
      value = Map.get(ctx.deps.preferences, String.to_atom(key), "not set")
      {:ok, %{key: key, value: value}}
    end,
    parameters: %{
      key: [type: :string, required: true]
    },
    context_aware: true
  )

conv_deps = %ConversationDeps{
  user_id: 999,
  preferences: %{theme: "dark", language: "en"},
  history_store: :fake_history
}

# First turn
messages = [
  %{role: :user, content: "Save my favorite color as blue"}
]

{:ok, response1} =
  Openrouter.Agent.run_with_history(
    messages,
    model: "openai/gpt-3.5-turbo",
    tools: [save_preference_tool, get_preference_tool],
    deps: conv_deps
  )

IO.puts("Turn 1: #{response1.content}")

# Second turn - context persists
messages = messages ++ [
  %{role: :assistant, content: response1.content},
  %{role: :user, content: "What's my current theme preference?"}
]

{:ok, response2} =
  Openrouter.Agent.run_with_history(
    messages,
    model: "openai/gpt-3.5-turbo",
    tools: [save_preference_tool, get_preference_tool],
    deps: conv_deps
  )

IO.puts("Turn 2: #{response2.content}\n")

# ============================================================================
# Example 6: RunContext Direct Usage
# ============================================================================

IO.puts("6. RunContext Direct Usage")
IO.puts("   Creating and manipulating RunContext manually\n")

# Create a RunContext
ctx = Openrouter.RunContext.new(
  deps: %{api_key: "secret", user: "alice"},
  model: "gpt-4",
  messages: []
)

IO.puts("Initial context:")
IO.puts("  - Model: #{ctx.model}")
IO.puts("  - Has deps: #{Openrouter.RunContext.has_deps?(ctx)}")
IO.puts("  - Message count: #{Openrouter.RunContext.message_count(ctx)}")

# Add messages
ctx =
  ctx
  |> Openrouter.RunContext.add_message(%{role: :user, content: "Hello"})
  |> Openrouter.RunContext.add_message(%{role: :assistant, content: "Hi there!"})

IO.puts("\nAfter adding messages:")
IO.puts("  - Message count: #{Openrouter.RunContext.message_count(ctx)}")

# Get last messages
last_two = Openrouter.RunContext.last_messages(ctx, 2)
IO.puts("  - Last 2 messages: #{length(last_two)} messages")

# Increment retry
ctx = Openrouter.RunContext.increment_retry(ctx)
IO.puts("\nAfter incrementing retry:")
IO.puts("  - Retry count: #{ctx.retry_count}")

# Update model
ctx = Openrouter.RunContext.update_model(ctx, "gpt-3.5-turbo")
IO.puts("\nAfter updating model:")
IO.puts("  - Model: #{ctx.model}")

# Convert to map
ctx_map = Openrouter.RunContext.to_map(ctx)
IO.puts("\nContext as map:")
IO.puts("  #{inspect(Map.keys(ctx_map))}\n")

# ============================================================================
# Example 7: Type-Safe Dependencies
# ============================================================================

IO.puts("7. Type-Safe Dependencies")
IO.puts("   Using structs for type safety\n")

defmodule PaymentDeps do
  @moduledoc "Type-safe payment service dependencies"
  defstruct [:payment_gateway, :merchant_id, :api_version]

  @type t :: %__MODULE__{
          payment_gateway: :stripe | :paypal | :square,
          merchant_id: String.t(),
          api_version: String.t()
        }

  def new(gateway, merchant_id) do
    %__MODULE__{
      payment_gateway: gateway,
      merchant_id: merchant_id,
      api_version: "v1"
    }
  end
end

process_payment_tool =
  Openrouter.Tool.new(
    :process_payment,
    "Process a payment through the configured gateway",
    fn ctx, %{amount: amount, currency: currency} ->
      # ctx.deps is a PaymentDeps struct - type-safe!
      gateway = ctx.deps.payment_gateway
      merchant_id = ctx.deps.merchant_id

      # Simulate payment processing
      result = %{
        gateway: gateway,
        merchant_id: merchant_id,
        amount: amount,
        currency: currency,
        status: "completed",
        transaction_id: "txn_#{:rand.uniform(999999)}"
      }

      {:ok, result}
    end,
    parameters: %{
      amount: [type: :number, required: true],
      currency: [type: :string, required: true, enum: ["USD", "EUR", "GBP"]]
    },
    context_aware: true
  )

# Create type-safe dependencies
payment_deps = PaymentDeps.new(:stripe, "merchant_12345")

{:ok, response} =
  Openrouter.Agent.run(
    "Process a payment of $99.99 USD",
    model: "openai/gpt-3.5-turbo",
    tools: [process_payment_tool],
    deps: payment_deps
  )

IO.puts("Result: #{response.content}\n")

IO.puts("=== All RunContext Examples Complete ===\n")
