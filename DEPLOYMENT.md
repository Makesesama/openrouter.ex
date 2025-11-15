# Production Deployment Guide

This guide covers best practices for deploying Elixir applications using `openrouter.ex` in production environments.

## Table of Contents

- [Environment Setup](#environment-setup)
- [Configuration Management](#configuration-management)
- [API Key Security](#api-key-security)
- [Cost Management](#cost-management)
- [Caching Strategy](#caching-strategy)
- [Error Handling](#error-handling)
- [Monitoring and Observability](#monitoring-and-observability)
- [Performance Optimization](#performance-optimization)
- [Scaling Considerations](#scaling-considerations)
- [Testing](#testing)
- [Deployment Checklist](#deployment-checklist)

## Environment Setup

### Dependencies

Ensure your `mix.exs` includes:

```elixir
defp deps do
  [
    {:openrouter, "~> 0.1.0"},
    {:req, "~> 0.5.0"},
    {:jason, "~> 1.4"},
    {:ecto, "~> 3.11"},  # For structured outputs

    # Production dependencies
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 1.0"},
    {:telemetry_poller, "~> 1.1"},

    # Optional but recommended
    {:sentry, "~> 10.0"},  # Error tracking
    {:ex_aws, "~> 2.5"},   # If using AWS services
  ]
end
```

### Elixir Version

Use Elixir 1.14+ and OTP 25+ for best performance and compatibility:

```bash
# Check versions
elixir --version
# Erlang/OTP 25 [erts-13.0] [source] [64-bit]
# Elixir 1.14.0
```

### Environment Variables

Set up required environment variables:

```bash
# Required
export OPENROUTER_API_KEY="or-..."

# Optional but recommended
export MIX_ENV=prod
export PHX_SERVER=true  # If using Phoenix
export SECRET_KEY_BASE="..."
export DATABASE_URL="..."
```

## Configuration Management

### Runtime Configuration

Use `config/runtime.exs` for environment-specific settings:

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  # OpenRouter configuration
  config :openrouter,
    api_key: System.get_env("OPENROUTER_API_KEY") || raise("OPENROUTER_API_KEY not set"),
    http_options: [
      receive_timeout: 60_000,
      retry: :transient,
      retry_delay: fn attempt -> 300 * attempt end,
      max_retries: 3
    ]

  # Cache configuration
  config :openrouter, :cache,
    backend: :ets,
    max_size: 10_000,
    default_ttl: :timer.hours(24),
    eviction_policy: :lru

  # Cost tracking
  config :openrouter, :cost_tracking,
    enabled: true,
    budget_warning_threshold: 0.8,
    monthly_budget: 500.00  # USD
end
```

### Application Supervision Tree

Add caching and cost tracking to your supervision tree:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start cache
      {Openrouter.Cache, [
        name: :openrouter_cache,
        backend: :ets,
        max_size: 10_000,
        default_ttl: :timer.hours(24)
      ]},

      # Start cost tracker
      {Openrouter.CostTracker, [
        name: :openrouter_costs,
        budget: Application.get_env(:openrouter, :monthly_budget)
      ]},

      # Your other processes...
      MyApp.Repo,
      MyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## API Key Security

### Never Commit API Keys

Add to `.gitignore`:

```gitignore
.env
.env.local
.env.*.local
config/*.secret.exs
```

### Use Secret Management

#### AWS Secrets Manager

```elixir
defmodule MyApp.Secrets do
  def get_openrouter_key do
    ExAws.SecretsManager.get_secret_value("prod/openrouter/api_key")
    |> ExAws.request()
    |> case do
      {:ok, %{"SecretString" => secret}} ->
        Jason.decode!(secret)["api_key"]
      {:error, reason} ->
        raise "Failed to fetch API key: #{inspect(reason)}"
    end
  end
end

# In config/runtime.exs
config :openrouter,
  api_key: MyApp.Secrets.get_openrouter_key()
```

#### HashiCorp Vault

```elixir
defmodule MyApp.Vault do
  def get_openrouter_key do
    {:ok, secret} = Vault.read("secret/data/openrouter")
    get_in(secret, ["data", "api_key"])
  end
end
```

### Environment-Based Keys

```elixir
# Development
config :openrouter,
  api_key: System.get_env("OPENROUTER_API_KEY_DEV")

# Production
config :openrouter,
  api_key: System.get_env("OPENROUTER_API_KEY_PROD")
```

## Cost Management

### Budget Enforcement

```elixir
defmodule MyApp.LLM do
  alias Openrouter.CostTracker

  def safe_chat(messages, opts \\ []) do
    # Check budget before making request
    case CostTracker.check_budget(:openrouter_costs) do
      {:ok, :within_budget} ->
        # Estimate cost first
        case Openrouter.TokenCounter.estimate_cost(messages, opts) do
          {:ok, estimate} when estimate.total_cost < 1.0 ->
            # Make request
            with {:ok, response} <- Openrouter.chat(messages, opts) do
              # Track cost
              CostTracker.track(:openrouter_costs, response.usage, opts)
              {:ok, response}
            end

          {:ok, estimate} ->
            {:error, {:cost_too_high, estimate.total_cost}}
        end

      {:error, :budget_exceeded} ->
        {:error, :budget_exceeded}
    end
  end
end
```

### Cost Alerts

```elixir
defmodule MyApp.CostMonitor do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Check costs every hour
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_costs, state) do
    stats = Openrouter.CostTracker.get_stats(:openrouter_costs)

    if stats.total_cost > 400.00 do
      # Send alert
      send_alert(:critical, "LLM costs exceeded $400: $#{stats.total_cost}")
    end

    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_costs, :timer.hours(1))
  end

  defp send_alert(level, message) do
    Logger.warning("[COST ALERT #{level}] #{message}")
    # Send to Slack, PagerDuty, etc.
  end
end
```

### Model Selection Strategy

```elixir
defmodule MyApp.ModelSelector do
  @doc """
  Choose appropriate model based on task complexity and budget
  """
  def select_model(complexity: :simple) do
    "openai/gpt-3.5-turbo"  # $0.0005/1K tokens
  end

  def select_model(complexity: :medium) do
    "anthropic/claude-3-haiku"  # $0.00025/1K input tokens
  end

  def select_model(complexity: :complex) do
    "openai/gpt-4"  # $0.03/1K tokens (use sparingly)
  end

  def select_model(complexity: :reasoning) do
    "anthropic/claude-3.5-sonnet"  # Best quality/cost ratio
  end
end
```

## Caching Strategy

### Cache Configuration

```elixir
defmodule MyApp.LLMCache do
  alias Openrouter.Cache

  @cache :openrouter_cache

  @doc """
  Cache chat responses based on determinism
  """
  def cached_chat(messages, opts \\ []) do
    temperature = Keyword.get(opts, :temperature, 1.0)

    # Deterministic responses (temp=0) - cache for 7 days
    ttl = if temperature == 0.0 do
      :timer.hours(24 * 7)
    else
      # Non-deterministic - shorter TTL or no cache
      :timer.hours(1)
    end

    key = Cache.chat_key(messages, opts)

    Cache.fetch(@cache, key, fn ->
      Openrouter.chat(messages, opts)
    end, ttl: ttl)
  end

  @doc """
  Cache embeddings indefinitely (they're deterministic)
  """
  def cached_embedding(text, opts \\ []) do
    Cache.fetch_embedding(@cache, text,
      compute_fn: fn -> Openrouter.embeddings(text, opts) end,
      ttl: :infinity
    )
  end
end
```

### Cache Warming

```elixir
defmodule MyApp.CacheWarmer do
  @doc """
  Pre-populate cache with common queries
  """
  def warm_cache do
    common_queries = [
      "What is machine learning?",
      "Explain REST APIs",
      "How does Elixir work?"
    ]

    Enum.each(common_queries, fn query ->
      MyApp.LLMCache.cached_chat(
        [%{role: "user", content: query}],
        model: "openai/gpt-3.5-turbo",
        temperature: 0
      )
    end)
  end
end
```

## Error Handling

### Graceful Degradation

```elixir
defmodule MyApp.RobustLLM do
  require Logger

  def chat_with_fallback(messages, opts \\ []) do
    primary_model = Keyword.get(opts, :model, "anthropic/claude-3.5-sonnet")

    case Openrouter.chat(messages, Keyword.put(opts, :model, primary_model)) do
      {:ok, response} ->
        {:ok, response}

      {:error, %{status: 429}} ->
        # Rate limited - try cheaper model
        Logger.warning("Rate limited on #{primary_model}, falling back")
        Openrouter.chat(messages, Keyword.put(opts, :model, "openai/gpt-3.5-turbo"))

      {:error, %{status: 503}} ->
        # Service unavailable - retry with backoff
        Logger.warning("Service unavailable, retrying...")
        Process.sleep(1000)
        Openrouter.chat(messages, opts)

      {:error, reason} ->
        Logger.error("LLM request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

### Circuit Breaker Pattern

```elixir
defmodule MyApp.CircuitBreaker do
  use GenServer

  defstruct failures: 0, state: :closed, last_failure: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def call(fun) do
    case GenServer.call(__MODULE__, :check_state) do
      :open ->
        {:error, :circuit_open}

      :closed ->
        try do
          result = fun.()
          GenServer.cast(__MODULE__, :success)
          {:ok, result}
        rescue
          e ->
            GenServer.cast(__MODULE__, :failure)
            {:error, e}
        end
    end
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:check_state, _from, state) do
    {:reply, state.state, state}
  end

  @impl true
  def handle_cast(:failure, state) do
    new_failures = state.failures + 1

    new_state = if new_failures >= 5 do
      # Open circuit after 5 failures
      schedule_half_open()
      %{state | state: :open, failures: new_failures, last_failure: System.monotonic_time()}
    else
      %{state | failures: new_failures}
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:success, state) do
    {:noreply, %{state | failures: 0, state: :closed}}
  end

  @impl true
  def handle_info(:try_half_open, state) do
    {:noreply, %{state | state: :closed, failures: 0}}
  end

  defp schedule_half_open do
    Process.send_after(self(), :try_half_open, :timer.seconds(30))
  end
end
```

## Monitoring and Observability

### Telemetry Events

```elixir
# lib/my_app/llm_metrics.ex
defmodule MyApp.LLMMetrics do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # LLM request metrics
      counter("openrouter.request.count"),
      counter("openrouter.request.error.count"),
      distribution("openrouter.request.duration", unit: {:native, :millisecond}),

      # Cost metrics
      sum("openrouter.cost.total"),
      last_value("openrouter.cost.current"),

      # Token metrics
      sum("openrouter.tokens.total"),
      distribution("openrouter.tokens.per_request"),

      # Cache metrics
      counter("openrouter.cache.hit.count"),
      counter("openrouter.cache.miss.count"),
      last_value("openrouter.cache.size"),
    ]
  end

  defp periodic_measurements do
    [
      {MyApp.LLMMetrics, :dispatch_cache_stats, []},
      {MyApp.LLMMetrics, :dispatch_cost_stats, []}
    ]
  end

  def dispatch_cache_stats do
    stats = Openrouter.Cache.stats(:openrouter_cache)

    :telemetry.execute(
      [:openrouter, :cache],
      %{
        hits: stats.hits,
        misses: stats.misses,
        size: stats.size,
        hit_rate: stats.hit_rate
      }
    )
  end

  def dispatch_cost_stats do
    stats = Openrouter.CostTracker.get_stats(:openrouter_costs)

    :telemetry.execute(
      [:openrouter, :cost],
      %{total: stats.total_cost, requests: stats.request_count}
    )
  end
end
```

### Instrumentation

```elixir
defmodule MyApp.InstrumentedLLM do
  def chat(messages, opts) do
    start_time = System.monotonic_time()

    result = Openrouter.chat(messages, opts)

    duration = System.monotonic_time() - start_time

    metadata = %{
      model: Keyword.get(opts, :model),
      message_count: length(messages)
    }

    case result do
      {:ok, response} ->
        :telemetry.execute(
          [:openrouter, :request],
          %{duration: duration, tokens: response.usage.total_tokens},
          metadata
        )

        {:ok, response}

      {:error, reason} ->
        :telemetry.execute(
          [:openrouter, :request, :error],
          %{duration: duration},
          Map.put(metadata, :error, inspect(reason))
        )

        {:error, reason}
    end
  end
end
```

### Logging

```elixir
# config/prod.exs
config :logger,
  level: :info,
  backends: [:console, {LoggerFileBackend, :file_log}]

config :logger, :file_log,
  path: "/var/log/my_app/prod.log",
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :model, :cost]
```

```elixir
defmodule MyApp.LoggedLLM do
  require Logger

  def chat(messages, opts) do
    model = Keyword.get(opts, :model)

    Logger.metadata(model: model)
    Logger.info("LLM request started", model: model, messages: length(messages))

    case Openrouter.chat(messages, opts) do
      {:ok, response} ->
        Logger.info("LLM request completed",
          tokens: response.usage.total_tokens,
          cost: response.usage.total_cost
        )
        {:ok, response}

      {:error, reason} ->
        Logger.error("LLM request failed", error: inspect(reason))
        {:error, reason}
    end
  end
end
```

## Performance Optimization

### Connection Pooling

```elixir
# config/runtime.exs
config :openrouter,
  http_options: [
    pool_timeout: 5_000,
    receive_timeout: 60_000,
    max_redirects: 3
  ]
```

### Request Batching

```elixir
defmodule MyApp.BatchProcessor do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def enqueue(request) do
    GenServer.cast(__MODULE__, {:enqueue, request})
  end

  @impl true
  def init(_opts) do
    schedule_flush()
    {:ok, %{queue: [], max_batch: 10}}
  end

  @impl true
  def handle_cast({:enqueue, request}, state) do
    new_queue = [request | state.queue]

    new_state = if length(new_queue) >= state.max_batch do
      flush_batch(new_queue)
      %{state | queue: []}
    else
      %{state | queue: new_queue}
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:flush, state) do
    flush_batch(state.queue)
    schedule_flush()
    {:noreply, %{state | queue: []}}
  end

  defp flush_batch([]), do: :ok
  defp flush_batch(requests) do
    # Process batch of requests
    Task.async_stream(requests, fn req ->
      Openrouter.chat(req.messages, req.opts)
    end, max_concurrency: 5)
    |> Enum.to_list()
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, 1000)
  end
end
```

### Streaming for Long Responses

```elixir
defmodule MyApp.StreamingLLM do
  def chat_stream(messages, opts) do
    Stream.resource(
      fn ->
        Openrouter.chat(messages, Keyword.put(opts, :stream, true))
      end,
      fn
        {:ok, response} ->
          {[response], :done}
        :done ->
          {:halt, :done}
        {:error, reason} ->
          raise "Stream error: #{inspect(reason)}"
      end,
      fn _ -> :ok end
    )
  end
end
```

## Scaling Considerations

### Horizontal Scaling

When running multiple instances:

1. **Use ETS cache with distributed Erlang** or **external cache** (Redis):

```elixir
# Option 1: External cache (Redis)
defmodule MyApp.RedisCache do
  def get(key) do
    Redix.command(:redix, ["GET", key])
  end

  def put(key, value, ttl) do
    Redix.command(:redix, ["SETEX", key, div(ttl, 1000), :erlang.term_to_binary(value)])
  end
end

# Option 2: Distributed cache with Horde
{:ok, _} = Horde.DynamicSupervisor.start_link(
  name: MyApp.CacheSupervisor,
  strategy: :one_for_one,
  distribution_strategy: Horde.UniformQuorumDistribution
)
```

2. **Centralize cost tracking**:

```elixir
# Use database for cost tracking across instances
defmodule MyApp.Costs do
  use Ecto.Schema

  schema "llm_costs" do
    field :model, :string
    field :tokens, :integer
    field :cost, :decimal
    field :instance_id, :string
    timestamps()
  end
end
```

### Load Balancing

```nginx
# nginx.conf
upstream my_app {
    least_conn;  # Use least connection algorithm
    server app1.example.com:4000;
    server app2.example.com:4000;
    server app3.example.com:4000;
}

server {
    listen 80;
    server_name api.example.com;

    location / {
        proxy_pass http://my_app;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # Increase timeout for LLM requests
        proxy_read_timeout 120s;
    }
}
```

## Testing

### Unit Tests

```elixir
defmodule MyApp.LLMTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  test "handles successful response" do
    expect(OpenrouterMock, :chat, fn _messages, _opts ->
      {:ok, %{choices: [%{message: %{content: "Hello"}}]}}
    end)

    assert {:ok, response} = MyApp.LLM.chat([%{role: "user", content: "Hi"}])
    assert response.choices |> List.first() |> get_in([:message, :content]) == "Hello"
  end

  test "handles rate limiting" do
    expect(OpenrouterMock, :chat, fn _messages, _opts ->
      {:error, %{status: 429, body: "Rate limited"}}
    end)

    assert {:error, %{status: 429}} = MyApp.LLM.chat([%{role: "user", content: "Hi"}])
  end
end
```

### Integration Tests

```elixir
defmodule MyApp.LLMIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  test "real API call" do
    messages = [%{role: "user", content: "Say 'test' and nothing else"}]

    assert {:ok, response} = Openrouter.chat(messages,
      model: "openai/gpt-3.5-turbo",
      temperature: 0,
      max_tokens: 10
    )

    assert String.contains?(response.choices |> List.first() |> get_in([:message, :content]), "test")
  end
end
```

Run integration tests separately:

```bash
mix test --only integration
```

## Deployment Checklist

### Pre-Deployment

- [ ] API key configured in production environment
- [ ] Cost tracking enabled with budget limits
- [ ] Caching configured and tested
- [ ] Error tracking (Sentry/Rollbar) integrated
- [ ] Monitoring and alerts configured
- [ ] Load testing completed
- [ ] Fallback strategies implemented
- [ ] Rate limiting configured
- [ ] Logging configured

### Deployment

- [ ] Run database migrations
- [ ] Deploy application
- [ ] Verify health checks
- [ ] Check cache warming
- [ ] Monitor error rates
- [ ] Verify cost tracking
- [ ] Test critical user flows
- [ ] Monitor API quotas

### Post-Deployment

- [ ] Monitor costs for 24 hours
- [ ] Check cache hit rates
- [ ] Review error logs
- [ ] Verify performance metrics
- [ ] Test failover scenarios
- [ ] Document any issues
- [ ] Update runbooks

## Example Production Configuration

```elixir
# config/runtime.exs (complete example)
import Config

if config_env() == :prod do
  # Database
  database_url = System.get_env("DATABASE_URL") || raise "DATABASE_URL not set"

  config :my_app, MyApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # Phoenix endpoint
  secret_key_base = System.get_env("SECRET_KEY_BASE") || raise "SECRET_KEY_BASE not set"

  config :my_app, MyAppWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: secret_key_base,
    server: true

  # OpenRouter
  config :openrouter,
    api_key: System.get_env("OPENROUTER_API_KEY") || raise "OPENROUTER_API_KEY not set",
    http_options: [
      receive_timeout: 60_000,
      pool_timeout: 5_000,
      retry: :transient,
      retry_delay: fn attempt -> 300 * attempt end,
      max_retries: 3
    ]

  # Cache
  config :openrouter, :cache,
    backend: :ets,
    max_size: String.to_integer(System.get_env("CACHE_MAX_SIZE") || "10000"),
    default_ttl: :timer.hours(24),
    eviction_policy: :lru

  # Cost tracking
  monthly_budget = System.get_env("LLM_MONTHLY_BUDGET") || "500.00"

  config :openrouter, :cost_tracking,
    enabled: true,
    budget_warning_threshold: 0.8,
    monthly_budget: String.to_float(monthly_budget)

  # Logging
  config :logger,
    level: :info,
    backends: [:console]

  # Error tracking
  config :sentry,
    dsn: System.get_env("SENTRY_DSN"),
    environment_name: :prod,
    enable_source_code_context: true,
    root_source_code_path: File.cwd!()
end
```

## Additional Resources

- [OpenRouter Documentation](https://openrouter.ai/docs)
- [Elixir Deployment Guide](https://hexdocs.pm/phoenix/deployment.html)
- [BEAM VM Tuning](https://erlang.org/doc/man/erl.html)
- [Telemetry Guide](https://hexdocs.pm/telemetry/readme.html)

## Support

For issues specific to this library, please open an issue on GitHub.

For OpenRouter API issues, contact support@openrouter.ai.
