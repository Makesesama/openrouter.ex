# OpenRouter Elixir SDK Design Document

## Overview

This document outlines the design for an **OpenRouter-focused** AI SDK in Elixir with production-grade reliability, seamless Phoenix integration, and support for agentic workflows.

**Primary Use Case**: Backend/server applications using OpenRouter to access any LLM (GPT-4, Claude, Llama, Gemini, etc.) through a single unified API.

**Philosophy**: OpenRouter already provides access to all major AI models. Rather than building adapters for each provider, we focus on making the best possible OpenRouter client while allowing users to implement custom providers if needed.

## Core Principles

Inspired by [Pydantic AI](https://ai.pydantic.dev/) and [FastAPI](https://fastapi.tiangolo.com/), we aim to bring that same "feeling" to Elixir AI development.

1. **Type Safety First**: Leverage Elixir's type system, Ecto schemas, and pattern matching for compile-time safety
2. **Backend-First**: Production-ready with proper supervision, connection pooling, and observability
3. **OpenRouter-First**: Built specifically for OpenRouter's API with first-class support for all features
4. **Extensible**: Provider behavior allows users to implement custom providers if needed
5. **Dependency Injection**: Type-safe context passing (inspired by Pydantic AI's RunContext)
6. **Agentic Workflows**: First-class support for tool calling, multi-turn conversations, and complex workflows
7. **Phoenix Integration**: Seamless integration with LiveView, Channels, and background jobs
8. **Streaming Support**: First-class support for streaming responses with structured events
9. **Structured Outputs**: Automatic validation and retry using Ecto schemas
10. **Composability**: Small, composable functions that can be combined (tools, toolsets, instructions)
11. **Observability**: Built-in telemetry and logging for production monitoring
12. **Testing-First**: Easy mocking and deterministic tests with test providers

## Architecture

### Model Selection

All models are accessed through OpenRouter using their standard model naming:

```elixir
# OpenRouter model format: "provider/model-name"
agent = Openrouter.new("openai/gpt-4")
agent = Openrouter.new("anthropic/claude-sonnet-4-0")
agent = Openrouter.new("meta-llama/llama-3.3-70b-instruct")
agent = Openrouter.new("google/gemini-2.0-flash")

# Runtime model override
{:ok, result} = Openrouter.chat(agent, "Hello", model: "anthropic/claude-3.5-sonnet")

# Default to a configured model
agent = Openrouter.new()  # Uses configured default
{:ok, result} = Openrouter.chat(agent, "Hello")
```

**Note**: Since we're OpenRouter-focused, all model names follow [OpenRouter's format](https://openrouter.ai/models).

### Provider Behavior (Optional - For Custom Providers)

While the library is built for OpenRouter, users can implement custom providers if needed:

```elixir
defmodule Openrouter.Provider do
  @moduledoc """
  Behavior for custom AI providers.

  OpenRouter is the default and only built-in provider.
  Implement this behavior if you need to use a different provider.
  """

  @type config :: map()
  @type message :: Openrouter.Message.t()
  @type params :: Openrouter.RequestParams.t()
  @type response :: Openrouter.Response.t()

  @callback name() :: String.t()

  @callback request(config, [message], params) ::
    {:ok, response} | {:error, term()}

  @callback request_stream(config, [message], params) ::
    {:ok, Enumerable.t()} | {:error, term()}

  @callback embeddings(config, [String.t()], params) ::
    {:ok, [list(float())]} | {:error, term()}
end

# Built-in OpenRouter provider
defmodule Openrouter.Provider.OpenRouter do
  @behaviour Openrouter.Provider
  @moduledoc """
  Default OpenRouter provider implementation.
  Handles all communication with the OpenRouter API.
  """

  def name, do: "openrouter"
  # Full implementation...
end

# Example: User-provided custom provider
defmodule MyApp.CustomProvider do
  @behaviour Openrouter.Provider

  def name, do: "custom"

  def request(config, messages, params) do
    # Custom implementation
  end
end

# Use custom provider
agent = Openrouter.new(provider: MyApp.CustomProvider)
```

### Dependency Injection via RunContext

Inspired by Pydantic AI's RunContext pattern for type-safe dependency injection:

```elixir
# Define your dependencies
defmodule SupportDeps do
  defstruct [:customer_id, :db_conn]

  @type t :: %__MODULE__{
    customer_id: integer(),
    db_conn: DBConnection.t()
  }
end

# Agent is generic over dependencies
agent = Openrouter.Agent.new(
  model: "openai/gpt-4",
  deps_type: SupportDeps,
  instructions: "You are a helpful support agent"
)

# Tools receive RunContext with typed dependencies
agent = Openrouter.Agent.tool(agent, :customer_balance, fn ctx, %{include_pending: pending} ->
  # ctx.deps is a SupportDeps struct - fully typed!
  balance = Database.get_balance(
    ctx.deps.db_conn,
    ctx.deps.customer_id,
    include_pending: pending
  )
  {:ok, balance}
end)

# Run with dependencies
deps = %SupportDeps{customer_id: 123, db_conn: conn}
{:ok, result} = Openrouter.Agent.run(agent, "What's my balance?", deps: deps)
```

### RunContext Structure

```elixir
defmodule Openrouter.RunContext do
  @moduledoc """
  Context passed to tools and dynamic instructions.

  Generic over the dependency type for type safety.
  """

  @type t(deps) :: %__MODULE__{
    deps: deps,
    messages: [Openrouter.Message.t()],
    retry_count: non_neg_integer(),
    model: String.t(),
    usage: Openrouter.Usage.t() | nil
  }

  defstruct [:deps, :messages, :retry_count, :model, :usage]
end
```

### Configuration

```elixir
# config/config.exs
config :openrouter,
  api_key: System.get_env("OPENROUTER_API_KEY"),
  base_url: "https://openrouter.ai/api/v1",
  default_model: "anthropic/claude-sonnet-4-0",
  app_name: "my-app",  # For OpenRouter tracking
  site_url: "https://myapp.com"  # Optional

# config/runtime.exs (production)
config :openrouter,
  api_key: System.fetch_env!("OPENROUTER_API_KEY")

# Runtime config per agent/client
agent = Openrouter.new(
  model: "openai/gpt-4",
  api_key: "or-...",  # Override default
  timeout: 30_000
)
```

## Core Capabilities

### 1. Text Generation

Simple, ergonomic API for text generation via OpenRouter:

```elixir
# Simple usage with default model
{:ok, response} = Openrouter.chat("What is the capital of France?")

# With options
{:ok, response} = Openrouter.chat(
  "Tell me a joke",
  model: "anthropic/claude-3.5-sonnet",
  temperature: 0.7,
  max_tokens: 100
)

# With conversation history
messages = [
  %{role: "system", content: "You are a helpful assistant"},
  %{role: "user", content: "Hello!"},
  %{role: "assistant", content: "Hi! How can I help?"},
  %{role: "user", content: "What's the weather?"}
]

{:ok, response} = Openrouter.chat(messages, model: "openai/gpt-4")

# With specific agent/client
agent = Openrouter.new(model: "anthropic/claude-sonnet-4-0")
{:ok, response} = Openrouter.chat(agent, "Hello!")
```

### 2. Structured Outputs (Objects)

Type-safe structured data extraction:

```elixir
# Define a schema
defmodule RecipeSchema do
  use Openrouter.Schema

  embedded_schema do
    field :name, :string
    field :ingredients, {:array, :string}
    field :steps, {:array, :string}
    field :prep_time, :integer
    field :difficulty, :string
  end
end

# Extract structured data
{:ok, recipe} = Openrouter.extract(
  "Give me a recipe for chocolate chip cookies",
  schema: RecipeSchema,
  model: "openai/gpt-4"
)

# recipe is a validated RecipeSchema struct
IO.inspect(recipe.name)
IO.inspect(recipe.ingredients)
```

Alternatively, using JSON schema directly:

```elixir
schema = %{
  type: "object",
  properties: %{
    name: %{type: "string"},
    age: %{type: "integer"},
    email: %{type: "string", format: "email"}
  },
  required: ["name", "age"]
}

{:ok, data} = Openrouter.extract(
  "Extract: John Doe is 30 years old, email john@example.com",
  json_schema: schema
)
```

### 3. Embeddings

Vector embeddings for semantic search:

```elixir
# Single text
{:ok, embedding} = Openrouter.embed(
  "The quick brown fox",
  model: "text-embedding-3-small"
)

# Batch embeddings
texts = ["Hello world", "Goodbye world", "How are you?"]
{:ok, embeddings} = Openrouter.embed_batch(texts, model: "text-embedding-3-small")

# Returns list of vectors
Enum.each(embeddings, fn vec ->
  IO.inspect(length(vec)) # e.g., 1536 dimensions
end)
```

### 4. Multimodal Content (Images, Videos, PDFs, Audio)

Inline multimodal support using content arrays:

```elixir
# Image from URL
{:ok, response} = Openrouter.chat([
  %{
    role: "user",
    content: [
      %{type: "text", text: "What's in this image?"},
      %{type: "image_url", image_url: %{url: "https://example.com/image.jpg"}}
    ]
  }
], model: "anthropic/claude-3.5-sonnet")

# Local image (base64 encoded)
image_data = File.read!("photo.jpg") |> Base.encode64()

{:ok, response} = Openrouter.chat([
  %{
    role: "user",
    content: [
      %{type: "text", text: "Describe this image"},
      %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,#{image_data}"}}
    ]
  }
])

# Helper for local images
{:ok, response} = Openrouter.chat([
  %{
    role: "user",
    content: [
      Openrouter.text("What's in this image?"),
      Openrouter.image(File.read!("photo.jpg"), format: :jpeg)
    ]
  }
])

# Video from URL or local file
{:ok, response} = Openrouter.chat([
  %{
    role: "user",
    content: [
      %{type: "text", text: "Describe what's happening in this video"},
      %{type: "video_url", video_url: %{url: "https://example.com/video.mp4"}}
    ]
  }
], model: "google/gemini-pro-vision")

# PDF document
{:ok, response} = Openrouter.chat([
  %{
    role: "user",
    content: [
      %{type: "text", text: "Summarize this document"},
      %{type: "file", file: %{
        filename: "report.pdf",
        file_data: "https://example.com/report.pdf"
      }}
    ]
  }
], plugins: [%{id: "pdf-text"}])

# Multiple images in one message
{:ok, response} = Openrouter.chat([
  %{
    role: "user",
    content: [
      Openrouter.text("Compare these images"),
      Openrouter.image_url("https://example.com/image1.jpg"),
      Openrouter.image_url("https://example.com/image2.jpg")
    ]
  }
])

# Helper module for ergonomic content building
alias Openrouter.Content

{:ok, response} = Openrouter.chat([
  %{
    role: "user",
    content: Content.build([
      text: "Analyze this document and image",
      pdf: "https://example.com/doc.pdf",
      image: File.read!("chart.png")
    ])
  }
])
```

### 5. Streaming

First-class streaming support:

```elixir
# Stream text chunks
Openrouter.chat_stream("Tell me a long story")
|> Stream.each(fn chunk ->
  IO.write(chunk.content)
end)
|> Stream.run()

# With more control
stream = Openrouter.chat_stream(
  "Write a poem",
  model: "gpt-4",
  temperature: 0.8
)

for event <- stream do
  case event do
    %{type: :content, content: text} -> IO.write(text)
    %{type: :done, usage: usage} -> IO.inspect(usage)
    %{type: :error, error: err} -> IO.puts("Error: #{inspect(err)}")
  end
end

# Phoenix LiveView integration
def handle_info({:stream_chunk, chunk}, socket) do
  {:noreply, stream_insert(socket, :messages, chunk)}
end
```

### 6. Tool Calling (Agentic Workflows)

Support for function/tool calling to enable agentic workflows:

```elixir
# Define tools
tools = [
  %{
    type: "function",
    function: %{
      name: "get_weather",
      description: "Get the current weather in a location",
      parameters: %{
        type: "object",
        properties: %{
          location: %{type: "string", description: "City name"},
          unit: %{type: "string", enum: ["celsius", "fahrenheit"]}
        },
        required: ["location"]
      }
    }
  },
  %{
    type: "function",
    function: %{
      name: "search_database",
      description: "Search the product database",
      parameters: %{
        type: "object",
        properties: %{
          query: %{type: "string"}
        }
      }
    }
  }
]

# Simple tool call
{:ok, response} = Openrouter.chat(
  "What's the weather in Paris?",
  model: "gpt-4",
  tools: tools
)

# Handle tool calls
case response do
  %{tool_calls: [%{function: %{name: "get_weather", arguments: args}} | _]} ->
    # Execute the function
    result = MyApp.Weather.get(args["location"])

    # Send result back to continue conversation
    {:ok, final_response} = Openrouter.chat([
      %{role: "user", content: "What's the weather in Paris?"},
      %{role: "assistant", tool_calls: response.tool_calls},
      %{role: "tool", tool_call_id: response.tool_calls.id, content: Jason.encode!(result)}
    ], tools: tools)

  %{content: content} ->
    # Regular response
    IO.puts(content)
end

# Higher-level agent loop
defmodule MyApp.Agent do
  use Openrouter.Agent

  # Define available tools
  def tools do
    [
      tool(:get_weather, "Get weather for a location", fn %{location: loc} ->
        MyApp.Weather.get(loc)
      end),

      tool(:search_db, "Search database", fn %{query: q} ->
        MyApp.DB.search(q)
      end)
    ]
  end

  # Agent automatically handles tool call loop
  def run(prompt) do
    Openrouter.Agent.chat(prompt,
      model: "gpt-4",
      tools: tools(),
      max_iterations: 5
    )
  end
end

# Usage
{:ok, result} = MyApp.Agent.run("Find weather in Paris and search for umbrellas")
```

### 7. Conversation Management

Built-in conversation state management for multi-turn interactions:

```elixir
# Start a conversation
{:ok, conversation} = Openrouter.Conversation.start(
  model: "gpt-4",
  system: "You are a helpful assistant"
)

# Add messages
conversation = Openrouter.Conversation.user(conversation, "Hello!")
{:ok, conversation, response} = Openrouter.Conversation.complete(conversation)

# Continue conversation
conversation = Openrouter.Conversation.user(conversation, "Tell me more")
{:ok, conversation, response} = Openrouter.Conversation.complete(conversation)

# Access history
messages = Openrouter.Conversation.messages(conversation)

# Persist conversation
conversation_id = conversation.id
:ok = Openrouter.Conversation.save(conversation, to: :ets)  # or custom backend

# Resume later
{:ok, conversation} = Openrouter.Conversation.load(conversation_id, from: :ets)

# GenServer-based conversation for stateful sessions
defmodule MyApp.ChatSession do
  use Openrouter.ConversationServer

  def start_link(user_id) do
    Openrouter.ConversationServer.start_link(__MODULE__,
      name: via_tuple(user_id),
      model: "gpt-4",
      system: "You are a helpful assistant"
    )
  end

  defp via_tuple(user_id) do
    {:via, Registry, {MyApp.Registry, {__MODULE__, user_id}}}
  end
end

# Usage in Phoenix controller/LiveView
{:ok, pid} = MyApp.ChatSession.start_link(user.id)
{:ok, response} = MyApp.ChatSession.send_message(pid, "Hello!")

# Streaming with conversation
MyApp.ChatSession.stream_message(pid, "Tell me a story")
|> Stream.each(fn chunk -> send(self(), {:chunk, chunk}) end)
|> Stream.run()
```

## Phoenix Integration

### LiveView Streaming

Seamless integration with Phoenix LiveView for real-time streaming:

```elixir
defmodule MyAppWeb.ChatLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, assign(socket, messages: [], current_response: "", streaming: false)}
  end

  def handle_event("send_message", %{"message" => msg}, socket) do
    # Add user message
    messages = socket.assigns.messages ++ [%{role: "user", content: msg}]

    # Start streaming in background
    task = Task.async(fn ->
      Openrouter.chat_stream(messages, model: "gpt-4")
    end)

    {:noreply,
     socket
     |> assign(messages: messages, streaming: true, task: task)
     |> stream_insert(:chunks, [])}
  end

  def handle_info({ref, stream}, socket) when socket.assigns.task.ref == ref do
    # Stream started, process chunks
    for event <- stream do
      send(self(), {:chunk, event})
    end
    {:noreply, socket}
  end

  def handle_info({:chunk, %{type: :content, content: text}}, socket) do
    current = socket.assigns.current_response <> text
    {:noreply, assign(socket, current_response: current)}
  end

  def handle_info({:chunk, %{type: :done}}, socket) do
    # Finalize message
    messages = socket.assigns.messages ++ [
      %{role: "assistant", content: socket.assigns.current_response}
    ]

    {:noreply,
     socket
     |> assign(messages: messages, current_response: "", streaming: false)}
  end
end
```

### Phoenix Channels

Real-time updates via Phoenix Channels:

```elixir
defmodule MyAppWeb.ChatChannel do
  use Phoenix.Channel

  def join("chat:" <> user_id, _params, socket) do
    # Start conversation server for this user
    {:ok, _pid} = MyApp.ChatSession.start_link(user_id)
    {:ok, assign(socket, user_id: user_id)}
  end

  def handle_in("message", %{"content" => content}, socket) do
    user_id = socket.assigns.user_id
    pid = MyApp.ChatSession.whereis(user_id)

    # Stream response back via channel
    Task.start(fn ->
      MyApp.ChatSession.stream_message(pid, content)
      |> Stream.each(fn chunk ->
        push(socket, "chunk", %{content: chunk.content})
      end)
      |> Stream.run()

      push(socket, "done", %{})
    end)

    {:noreply, socket}
  end
end
```

### Background Jobs (Oban Integration)

Process AI requests in background jobs:

```elixir
defmodule MyApp.Workers.SummarizeDocument do
  use Oban.Worker, queue: :ai, max_attempts: 3

  @impl Oban.Worker
  def perform(%{args: %{"document_id" => doc_id}}) do
    document = MyApp.Repo.get!(Document, doc_id)

    {:ok, summary} = Openrouter.chat([
      %{role: "user", content: [
        Openrouter.text("Summarize this document:"),
        Openrouter.pdf(document.file_url)
      ]}
    ], model: "gpt-4")

    MyApp.Repo.update!(Document.changeset(document, %{
      summary: summary.content,
      summarized_at: DateTime.utc_now()
    }))

    :ok
  end
end

# Usage
%{document_id: doc.id}
|> MyApp.Workers.SummarizeDocument.new()
|> Oban.insert()

# Batch processing with concurrency control
defmodule MyApp.Workers.BatchEmbeddings do
  use Oban.Worker, queue: :ai_embeddings

  @impl Oban.Worker
  def perform(%{args: %{"texts" => texts, "batch_id" => batch_id}}) do
    # Process in chunks to respect rate limits
    texts
    |> Enum.chunk_every(100)
    |> Enum.each(fn chunk ->
      {:ok, embeddings} = Openrouter.embed_batch(chunk, model: "text-embedding-3-small")
      MyApp.Embeddings.store_batch(batch_id, embeddings)
      Process.sleep(1000)  # Rate limiting
    end)

    :ok
  end
end
```

### Phoenix Context Integration

Clean integration with Phoenix contexts:

```elixir
defmodule MyApp.AI do
  @moduledoc """
  AI context for application AI features
  """

  alias MyApp.Repo
  alias MyApp.AI.{Conversation, Message}

  def chat(user, message_content) do
    conversation = get_or_create_conversation(user)

    # Add user message
    create_message(conversation, %{
      role: "user",
      content: message_content
    })

    # Get AI response
    messages = list_messages(conversation)

    {:ok, response} = Openrouter.chat(
      messages |> Enum.map(&message_to_map/1),
      model: "gpt-4"
    )

    # Store AI response
    {:ok, ai_message} = create_message(conversation, %{
      role: "assistant",
      content: response.content,
      metadata: %{
        model: response.model,
        tokens: response.usage
      }
    })

    {:ok, ai_message}
  end

  def extract_entities(text) do
    {:ok, result} = Openrouter.extract(
      text,
      json_schema: entity_schema(),
      model: "gpt-4"
    )

    {:ok, result}
  end

  defp entity_schema do
    %{
      type: "object",
      properties: %{
        entities: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              name: %{type: "string"},
              type: %{type: "string"},
              confidence: %{type: "number"}
            }
          }
        }
      }
    }
  end
end
```

## Production Patterns

### Supervision & Fault Tolerance

Production-ready supervision trees:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Connection pool for HTTP requests
      {Finch, name: Openrouter.Finch},

      # Registry for conversation processes
      {Registry, keys: :unique, name: MyApp.ChatRegistry},

      # DynamicSupervisor for chat sessions
      {DynamicSupervisor, name: MyApp.ChatSupervisor, strategy: :one_for_one},

      # Optional: Persistent connection to AI providers
      {Openrouter.ConnectionPool, provider: :openrouter, pool_size: 10}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

# Fault-tolerant client wrapper
defmodule MyApp.AI.Client do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def chat(messages, opts \\ []) do
    GenServer.call(__MODULE__, {:chat, messages, opts}, :infinity)
  end

  @impl true
  def init(opts) do
    client = Openrouter.new(provider: :openrouter)
    {:ok, %{client: client, opts: opts}}
  end

  @impl true
  def handle_call({:chat, messages, opts}, _from, state) do
    result = with_retry(fn ->
      Openrouter.chat(state.client, messages, opts)
    end)

    {:reply, result, state}
  end

  defp with_retry(fun, attempts \\ 3) do
    case fun.() do
      {:ok, _} = success -> success
      {:error, %{type: :rate_limit, retry_after: seconds}} when attempts > 0 ->
        Logger.warn("Rate limited, retrying after #{seconds}s")
        Process.sleep(seconds * 1000)
        with_retry(fun, attempts - 1)
      {:error, _} = error when attempts > 0 ->
        Process.sleep(1000)
        with_retry(fun, attempts - 1)
      error -> error
    end
  end
end
```

### Telemetry & Observability

Built-in telemetry events for monitoring:

```elixir
# Telemetry events emitted
[:openrouter, :request, :start]     # %{system_time: time, request_id: id}
[:openrouter, :request, :stop]      # %{duration: duration, tokens: usage, model: model}
[:openrouter, :request, :exception] # %{kind: kind, reason: reason, stacktrace: stacktrace}
[:openrouter, :stream, :start]      # %{system_time: time}
[:openrouter, :stream, :chunk]      # %{chunk_size: size, total_chunks: count}
[:openrouter, :stream, :stop]       # %{duration: duration, total_tokens: tokens}

# Attach handlers
:telemetry.attach_many(
  "aikit-logger",
  [
    [:openrouter, :request, :start],
    [:openrouter, :request, :stop],
    [:openrouter, :request, :exception]
  ],
  &MyApp.Telemetry.handle_event/4,
  nil
)

defmodule MyApp.Telemetry do
  require Logger

  def handle_event([:openrouter, :request, :start], _measurements, metadata, _config) do
    Logger.info("AI request started: #{inspect(metadata)}")
  end

  def handle_event([:openrouter, :request, :stop], measurements, metadata, _config) do
    Logger.info("AI request completed",
      duration: measurements.duration,
      tokens: metadata.tokens,
      model: metadata.model
    )
  end

  def handle_event([:openrouter, :request, :exception], _measurements, metadata, _config) do
    Logger.error("AI request failed",
      error: metadata.reason,
      stacktrace: metadata.stacktrace
    )
  end
end

# LiveDashboard integration (optional)
defmodule MyApp.AIMetrics do
  use GenServer

  def init(_) do
    :telemetry.attach_many(
      "ai-metrics",
      [[:openrouter, :request, :stop]],
      &handle_metrics/4,
      nil
    )

    {:ok, %{total_requests: 0, total_tokens: 0, errors: 0}}
  end

  defp handle_metrics([:openrouter, :request, :stop], measurements, metadata, _) do
    # Update metrics
    :telemetry.execute(
      [:my_app, :ai, :tokens],
      %{count: metadata.tokens.total},
      metadata
    )
  end
end
```

### Configuration & Secrets

Production-ready configuration:

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :openrouter,
    default_provider: :openrouter,
    providers: %{
      openrouter: [
        api_key: System.fetch_env!("OPENROUTER_API_KEY"),
        base_url: System.get_env("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1"),
        timeout: String.to_integer(System.get_env("AI_TIMEOUT", "60000"))
      ],
      openai: [
        api_key: System.get_env("OPENAI_API_KEY"),
        organization: System.get_env("OPENAI_ORG_ID")
      ]
    },
    telemetry: true,
    pool_size: String.to_integer(System.get_env("AI_POOL_SIZE", "10"))
end

# Application config
config :openrouter,
  # Rate limiting
  rate_limit: [
    requests_per_minute: 60,
    tokens_per_minute: 90_000
  ],

  # Retry configuration
  retry: [
    max_attempts: 3,
    base_backoff: 1000,
    max_backoff: 10_000
  ],

  # Default models per capability
  defaults: %{
    chat: "openai/gpt-4",
    embeddings: "openai/text-embedding-3-small",
    vision: "anthropic/claude-3.5-sonnet"
  }
```

## Dependencies

### HTTP Client: Req

We'll use [Req](https://hexdocs.pm/req) as our HTTP client for the following reasons:

- **Modern & High-level**: Built-in support for JSON, retries, and middleware
- **Excellent DX**: Clean, pipeline-friendly API that matches Elixir idioms
- **Streaming Support**: First-class Server-Sent Events (SSE) support for streaming responses
- **Built on Finch**: Uses Finch under the hood for connection pooling and production-readiness
- **Extensible**: Plugin architecture for custom request/response handling

Example usage in our HTTP wrapper:

```elixir
defmodule Openrouter.HTTP do
  def request(client, method, path, opts \\ []) do
    Req.request(
      method: method,
      url: build_url(client, path),
      headers: build_headers(client),
      json: opts[:json],
      receive_timeout: client.timeout || 60_000
    )
  end

  def stream_request(client, method, path, opts \\ []) do
    Req.request!(
      method: method,
      url: build_url(client, path),
      headers: build_headers(client),
      json: opts[:json],
      into: :self  # SSE streaming
    )
  end
end
```

### Other Dependencies

**Required:**
- `req` ~> 0.5 - HTTP client with streaming support
- `jason` ~> 1.4 - JSON encoding/decoding (fast, widely used)
- `telemetry` ~> 1.2 - Observability and metrics

**Optional:**
- `ecto` ~> 3.11 - For schema definitions in structured outputs
- `nimble_options` ~> 1.1 - Configuration validation

## Module Structure

```
lib/
├── openrouter.ex                          # Main public API
├── openrouter/
│   ├── application.ex                # Optional Application for supervision tree
│   ├── client.ex                     # Client struct and creation
│   ├── config.ex                     # Configuration handling & validation
│   ├── provider.ex                   # Provider behaviour
│   ├── schema.ex                     # Schema definition for structured outputs
│   ├── http.ex                       # HTTP client wrapper (uses Req)
│   ├── stream.ex                     # Streaming utilities
│   ├── content.ex                    # Content builders (text, image, video, pdf helpers)
│   │
│   ├── conversation.ex               # Conversation state management
│   ├── conversation_server.ex        # GenServer-based conversation handling
│   │
│   ├── agent.ex                      # Agentic workflow support
│   ├── tool.ex                       # Tool/function calling utilities
│   │
│   ├── provider/
│   │   ├── openrouter.ex            # OpenRouter implementation
│   │   └── test.ex                   # Test provider for mocking       # Shared adapter utilities
│   │
│   ├── types/
│   │   ├── message.ex               # Message types and content types
│   │   ├── response.ex              # Response types
│   │   ├── embedding.ex             # Embedding types
│   │   ├── tool_call.ex             # Tool call types
│   │   └── error.ex                 # Error types
│   │
│   ├── telemetry.ex                  # Telemetry event definitions
│   │
│   └── utils/
│       ├── validation.ex            # Input validation
│       ├── retry.ex                 # Retry logic with backoff
│       ├── encoding.ex              # Base64 encoding helpers
│       └── rate_limiter.ex          # Rate limiting utilities
```

## Error Handling

Consistent error format across all providers:

```elixir
case Openrouter.chat("Hello") do
  {:ok, response} ->
    # Success
    IO.puts(response.content)

  {:error, %Openrouter.Error{type: :rate_limit, message: msg, retry_after: seconds}} ->
    # Rate limited
    Process.sleep(seconds * 1000)
    retry()

  {:error, %Openrouter.Error{type: :invalid_request, message: msg}} ->
    # Bad request
    Logger.error("Invalid request: #{msg}")

  {:error, %Openrouter.Error{type: :provider_error, message: msg, original: original}} ->
    # Provider-specific error
    Logger.error("Provider error: #{msg}")
end
```

## Developer Experience Goals

### 1. Sensible Defaults

```elixir
# Should work with minimal config
Openrouter.chat("Hello") # Uses default provider and model
```

### 2. Progressive Disclosure

```elixir
# Simple for basic use
Openrouter.chat("Hello")

# More options as needed
Openrouter.chat("Hello", model: "gpt-4", temperature: 0.7)

# Full control
client = Openrouter.new(provider: :openai, api_key: "...", timeout: 30_000)
Openrouter.chat(client, messages, model: "gpt-4", temperature: 0.7, max_tokens: 100)
```

### 3. Pipeline Friendly

```elixir
"Tell me about Elixir"
|> Openrouter.chat(model: "gpt-4")
|> case do
  {:ok, response} -> response.content
  {:error, _} -> "Error occurred"
end
|> String.upcase()
```

### 4. LiveView Integration

```elixir
defmodule MyAppWeb.ChatLive do
  use Phoenix.LiveView

  def handle_event("send_message", %{"message" => msg}, socket) do
    task = Task.async(fn ->
      Openrouter.chat_stream(msg, model: "gpt-4")
    end)

    {:noreply, assign(socket, task: task)}
  end

  def handle_info({ref, stream}, socket) when socket.assigns.task.ref == ref do
    for event <- stream do
      send(self(), {:stream_event, event})
    end
    {:noreply, socket}
  end

  def handle_info({:stream_event, %{type: :content, content: text}}, socket) do
    {:noreply, stream_insert(socket, :chunks, %{text: text})}
  end
end
```

## Testing Strategy

### Provider Mocking

```elixir
# Test mode with mock provider
defmodule Openrouter.Providers.Mock do
  @behaviour Openrouter.Provider

  def chat(_config, _params) do
    {:ok, %{content: "Mock response"}}
  end
end

# In tests
config :openrouter, default_provider: Openrouter.Providers.Mock

test "chat returns response" do
  assert {:ok, response} = Openrouter.chat("Hello")
  assert response.content == "Mock response"
end
```

## Decisions Made

- **HTTP Client**: Req (modern, excellent DX, built-in SSE streaming support)
- **Streaming**: Elixir Streams (idiomatic, composable with existing code)
- **Telemetry**: Yes, built-in for production observability
- **Rate Limiting**: Built-in utilities provided, but optional
- **Backend-First**: Production-ready with supervision trees, connection pooling
- **Agentic Support**: First-class tool calling and conversation management

## Open Questions

1. **Naming**: Should the library be called `AIKit`, `ExLLM`, `Inference`, or keep `OpenRouter`?
   - If provider-agnostic, probably not `OpenRouter`
   - `AIKit` is generic and extensible
   - `Inference` is technical but clear
   - Consider: `ExAI`, `Conductor`, `Nexus`

2. **Conversation Storage**: What backends to support for conversation persistence?
   - ETS (in-memory, built-in)
   - Mnesia (distributed)
   - Postgres/Ecto (database-backed)
   - Custom adapter pattern?

3. **Token Counting**: Should we include token counting utilities?
   ```elixir
   Openrouter.count_tokens("Hello world", model: "gpt-4")
   ```
   - Would require model-specific tokenizers (tiktoken for OpenAI, etc.)
   - Or use API endpoints where available

4. **Caching**: Should we provide built-in response caching?
   ```elixir
   Openrouter.chat("Hello", cache: true, cache_ttl: 3600)
   ```
   - Cache key generation strategy?
   - Integration with Cachex, Nebulex, or custom?

5. **Cost Tracking**: Track API costs across requests?
   - Would need cost database per model
   - Real-time tracking vs. post-request analysis?

6. **Prompt Management**: Should we include prompt template utilities?
   ```elixir
   defmodule MyApp.Prompts do
     use Openrouter.Prompts

     prompt :summarize, """
     Summarize the following text in {{length}} sentences:
     {{text}}
     """
   end

   Openrouter.chat(MyApp.Prompts.summarize(text: doc, length: 3))
   ```

7. **Testing Utilities**: Provide test helpers for recording/replaying AI interactions?
   ```elixir
   use Openrouter.TestCase, mode: :record  # or :replay, :passthrough
   ```

## Implementation Roadmap

### Phase 1: Core Foundation (MVP)
1. **Choose library name** and set up project structure
2. **Core types and behaviors**
   - Define Provider behavior
   - Message, Response, Error types
   - Client struct
3. **HTTP layer**
   - Req-based HTTP client
   - Basic error handling
   - Request/response transformation
4. **OpenRouter provider**
   - Chat completions
   - Embeddings
   - Basic streaming
5. **Configuration & validation**
   - Config module with runtime config
   - Environment variable support
6. **Basic telemetry**
   - Request lifecycle events
   - Error tracking
7. **Tests**
   - Mock provider for testing
   - Unit tests for core functionality

### Phase 2: Production Readiness
1. **Streaming improvements**
   - Full SSE support
   - Error handling in streams
   - Backpressure handling
2. **Multimodal content**
   - Content builders (image, video, PDF)
   - Base64 encoding helpers
   - OpenRouter-specific multimodal features
3. **OpenRouter-specific features**
   - Model routing preferences
   - Provider fallbacks
   - Cost tracking per model
   - Site/app name configuration
4. **Retry logic & fault tolerance**
   - Exponential backoff
   - Rate limit handling (OpenRouter-specific)
   - Circuit breaker pattern
5. **Rate limiting utilities**
   - Token bucket implementation
   - OpenRouter rate limits
6. **Enhanced telemetry**
   - Stream events
   - Token usage tracking
   - Cost tracking
   - Performance metrics

### Phase 3: Agentic Workflows
1. **RunContext & Dependency Injection** (Pydantic AI pattern)
   - RunContext struct generic over deps
   - Type-safe dependency passing
   - Context available in tools and instructions
2. **Tool calling support**
   - Tool definition utilities
   - Tool call parsing
   - Function execution framework
   - Tool decorator/macro API
3. **Conversation management**
   - Conversation struct and API
   - Message history management
   - ETS-based persistence
4. **Agent framework**
   - Agent behavior/macro
   - Agent generic over deps and output type
   - Automatic tool execution loop
   - Max iteration safety
5. **ConversationServer**
   - GenServer implementation
   - Registry integration
   - Streaming support

### Phase 4: Phoenix Integration & Advanced Features
1. **Phoenix helpers**
   - LiveView integration guides
   - Channel integration examples
   - Oban worker examples
2. **Structured outputs**
   - JSON schema support
   - Ecto schema integration
   - Schema validation
3. **Advanced features** (based on user feedback)
   - Conversation persistence adapters
   - Caching layer
   - Prompt templates
   - Token counting
   - Cost tracking
   - Testing utilities

### Phase 5: Polish & Documentation
1. **Comprehensive documentation**
   - Getting started guide
   - API reference
   - Phoenix integration guide
   - Agentic workflow guide
   - Migration guides for different providers
2. **Example applications**
   - Simple chat CLI
   - Phoenix LiveView chat
   - Agent with tools example
   - RAG (Retrieval Augmented Generation) example
3. **Performance optimization**
   - Connection pooling tuning
   - Memory optimization
   - Benchmarking suite
4. **Production guides**
   - Deployment best practices
   - Monitoring & alerting setup
   - Cost optimization strategies

## Design Influences from Pydantic AI

This design is heavily influenced by [Pydantic AI](https://ai.pydantic.dev/), which we analyzed in depth (see `PYDANTIC_AI_ANALYSIS.md`). Key patterns we're adopting:

### 1. Dependency Injection via RunContext
**Their approach:** Generic `RunContext[AgentDepsT]` passed to all tools and dynamic instructions
**Our adaptation:** Same pattern with Elixir typespecs and structs

### 2. Generic Agent Types
**Their approach:** `Agent[AgentDepsT, OutputDataT]` - type-safe at compile time
**Our adaptation:** Typespecs with `agent(deps, output)` for similar guarantees

### 3. Unified Model Interface
**Their approach:** Simple "provider:model" string format (e.g., "openai:gpt-4")
**Our adaptation:** Identical approach with runtime parsing

### 4. Structured Outputs with Auto-Retry
**Their approach:** Pydantic validation with automatic retry when LLM returns invalid data
**Our adaptation:** Ecto schema validation with retry logic

### 5. Decorator Pattern for Tools
**Their approach:** `@agent.tool` decorator with automatic docstring → tool description
**Our adaptation:** Macros/attributes for similar ergonomics

### 6. Toolsets for Modularity
**Their approach:** `AbstractToolset` for reusable tool collections
**Our adaptation:** Toolset behavior with composable implementations

### 7. Built-in Telemetry
**Their approach:** OpenTelemetry integration with zero-code instrumentation
**Our adaptation:** Elixir `:telemetry` with similar ease of use

### 8. Testing Utilities
**Their approach:** `TestModel` for deterministic testing
**Our adaptation:** Test provider behavior implementation

### Key Differences (Elixir Strengths)

While Pydantic AI is excellent, we can leverage Elixir's unique strengths:

1. **OTP for State Management** - GenServers for stateful conversations vs. their stateless approach
2. **Process Supervision** - Fault tolerance built into the BEAM
3. **Pattern Matching** - Elegant message/event handling
4. **Phoenix Integration** - First-class LiveView and Channel support
5. **Concurrent Streams** - Native actor model for streaming

## References

### Inspiration & Similar Projects
- [Pydantic AI](https://ai.pydantic.dev/) - Python AI framework (primary inspiration)
- [Vercel AI SDK](https://sdk.vercel.ai/docs) - TypeScript AI SDK with excellent DX
- [LangChain](https://python.langchain.com/) - Python AI framework (agents, chains)
- [Instructor](https://github.com/jxnl/instructor) - Structured outputs for Python
- [FastAPI](https://fastapi.tiangolo.com/) - The "feeling" we want to bring to Elixir AI

### API Documentation
- [OpenRouter API](https://openrouter.ai/docs) - Primary provider documentation
- [OpenRouter Multimodal](https://openrouter.ai/docs/features/multimodal) - Images, PDFs, video support
- [OpenAI API](https://platform.openai.com/docs/api-reference) - API reference
- [Anthropic API](https://docs.anthropic.com/claude/reference) - Claude API docs

### Elixir Ecosystem
- [Req](https://hexdocs.pm/req) - HTTP client
- [Telemetry](https://hexdocs.pm/telemetry) - Observability primitives
- [Phoenix](https://hexdocs.pm/phoenix) - Web framework
- [Oban](https://hexdocs.pm/oban) - Background job processing
- [ExUnit Mox](https://hexdocs.pm/mox) - Testing with mocks and behaviors
