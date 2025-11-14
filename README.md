# Openrouter.ex

[![Hex.pm](https://img.shields.io/hexpm/v/openrouter.svg)](https://hex.pm/packages/openrouter)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/openrouter)

A **production-ready** Elixir SDK for [OpenRouter](https://openrouter.ai/), bringing the best of Pydantic AI and FastAPI patterns to Elixir AI development.

## Why OpenRouter?

[OpenRouter](https://openrouter.ai/) provides unified access to **200+ AI models** through a single API:

- **OpenAI**: GPT-4, GPT-3.5, o1, o1-mini, etc.
- **Anthropic**: Claude 3.5 Sonnet, Claude 4, etc.
- **Google**: Gemini 2.0 Flash, Gemini Pro, etc.
- **Meta**: Llama 3.3 70B, Llama 3.1, etc.
- **Mistral**: Mistral Large, Mixtral, etc.
- **And 200+ more models**

One SDK, all models. No need to build separate clients for each provider.

## Features

### 🎯 **Backend-First Design**
- Production-ready with proper OTP supervision
- GenServer-based stateful conversations
- Connection pooling via Req/Finch
- Built-in telemetry and observability
- Exponential backoff retry logic

### 🤖 **Agentic Workflows**
- **Tool/Function Calling**: LLMs can call Elixir functions
- **Automatic Tool Execution**: Agent loops handle tool calls automatically
- **RunContext**: Type-safe dependency injection (inspired by Pydantic AI)
- **Conversation Management**: Both stateless and stateful APIs
- **Max Iterations Safety**: Prevents infinite loops

### 🔒 **Type Safety & Validation**
- **Structured Outputs**: Extract validated data with Ecto schemas
- **Automatic Retry**: Retry with error feedback when validation fails
- **JSON Schema Generation**: From your Ecto schemas
- **Compile-time Safety**: Full typespec coverage

### 🎨 **Multimodal Support**
- **Images**: URLs or base64-encoded (JPEG, PNG, GIF, WebP)
- **Video**: MP4, WebM support
- **PDFs**: Document processing
- **Audio**: Audio file support
- **Content Builders**: Ergonomic helpers for complex content

### 🔌 **Phoenix Integration Ready**
- LiveView streaming support
- Phoenix Channels integration
- Oban background job examples
- Supervision tree compatible

### 📊 **Production Features**
- Comprehensive telemetry events
- Retry logic with exponential backoff
- Rate limit handling
- Error types and recovery
- 1350+ tests (unit + integration)

## Quick Start

### Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:openrouter, "~> 0.1.0"}
  ]
end
```

Configure your API key:

```elixir
# config/config.exs
config :openrouter,
  api_key: System.get_env("OPENROUTER_API_KEY")

# Or in config/runtime.exs (recommended for production)
config :openrouter,
  api_key: System.fetch_env!("OPENROUTER_API_KEY")
```

### Simple Chat

```elixir
# Basic question
{:ok, response} = Openrouter.chat(
  "What is the capital of France?",
  model: "anthropic/claude-3.5-sonnet"
)

IO.puts(response.content)
# => "The capital of France is Paris."

# With conversation history
messages = [
  %{role: :system, content: "You are a helpful assistant"},
  %{role: :user, content: "Hello!"},
  %{role: :assistant, content: "Hi! How can I help?"},
  %{role: :user, content: "What's the weather?"}
]

{:ok, response} = Openrouter.chat(messages, model: "openai/gpt-4")
```

### Streaming Responses

```elixir
{:ok, stream} = Openrouter.chat_stream(
  "Write me a story about a robot",
  model: "openai/gpt-4"
)

stream
|> Stream.each(fn chunk -> IO.write(chunk.content) end)
|> Stream.run()
```

### Structured Data Extraction

Extract validated, typed data from unstructured text:

```elixir
defmodule RecipeSchema do
  use Openrouter.Schema

  embedded_schema do
    field :name, :string
    field :ingredients, {:array, :string}
    field :steps, {:array, :string}
    field :prep_time, :integer
    field :difficulty, :string
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :ingredients, :steps, :prep_time, :difficulty])
    |> validate_required([:name, :ingredients, :steps])
    |> validate_inclusion(:difficulty, ["easy", "medium", "hard"])
  end
end

{:ok, recipe} = Openrouter.extract(
  "Give me a recipe for chocolate chip cookies",
  schema: RecipeSchema,
  model: "openai/gpt-4"
)

# recipe is a validated RecipeSchema struct!
IO.inspect(recipe.name)
IO.inspect(recipe.ingredients)
```

**The library automatically:**
- ✅ Generates JSON schema from your Ecto schema
- ✅ Validates the LLM response
- ✅ Retries with error feedback if validation fails
- ✅ Returns a properly typed struct

### Tool Calling & Agentic Workflows

Define tools that LLMs can call:

```elixir
# Define a tool
weather_tool = Openrouter.Tool.new(
  :get_weather,
  "Get current weather for a location",
  fn %{location: location} ->
    # Your implementation
    {:ok, "Sunny, 72°F in #{location}"}
  end,
  parameters: %{
    location: [type: :string, required: true, description: "City name"]
  }
)

# Agent automatically handles tool execution loop
{:ok, result} = Openrouter.Agent.run(
  "What's the weather in Paris?",
  model: "openai/gpt-4",
  tools: [weather_tool]
)

IO.puts(result.content)
# => "The weather in Paris is sunny and 72°F"
```

### Dependency Injection with RunContext

Pass dependencies to context-aware tools:

```elixir
# Define your dependencies
defmodule AppDeps do
  defstruct [:db_conn, :user_id, :api_key]
end

# Context-aware tool
balance_tool = Openrouter.Tool.new(
  :get_balance,
  "Get user account balance",
  fn ctx, _params ->
    # ctx.deps contains your AppDeps struct
    balance = MyApp.DB.get_balance(ctx.deps.db_conn, ctx.deps.user_id)
    {:ok, balance}
  end,
  context_aware: true
)

# Run with dependencies
deps = %AppDeps{db_conn: MyApp.Repo, user_id: 123, api_key: "secret"}

{:ok, result} = Openrouter.Agent.run(
  "What's my balance?",
  model: "gpt-4",
  tools: [balance_tool],
  deps: deps
)
```

### Conversation Management

**Stateless (Functional):**

```elixir
{:ok, conv} = Openrouter.Conversation.start(
  model: "gpt-4",
  system: "You are a helpful assistant"
)

conv = Openrouter.Conversation.user(conv, "Hello!")
{:ok, conv, response} = Openrouter.Conversation.complete(conv)

conv = Openrouter.Conversation.user(conv, "Tell me more")
{:ok, conv, response} = Openrouter.Conversation.complete(conv)

# Save for later
:ok = Openrouter.Conversation.save(conv, to: :ets)
```

**Stateful (GenServer):**

```elixir
{:ok, pid} = Openrouter.ConversationServer.start_link(
  model: "gpt-4",
  system: "You are a helpful assistant"
)

{:ok, response1} = Openrouter.ConversationServer.send_message(pid, "Hello!")
{:ok, response2} = Openrouter.ConversationServer.send_message(pid, "Tell me more")

# State is automatically maintained!
```

### Multimodal Content

```elixir
# Image from URL
{:ok, response} = Openrouter.chat([
  %{
    role: :user,
    content: [
      Openrouter.Content.text("What's in this image?"),
      Openrouter.Content.image_url("https://example.com/image.jpg")
    ]
  }
], model: "anthropic/claude-3.5-sonnet")

# Local image (base64 encoded)
image_data = File.read!("photo.jpg")
{:ok, response} = Openrouter.chat([
  %{
    role: :user,
    content: [
      Openrouter.Content.text("Describe this image"),
      Openrouter.Content.image(image_data, format: :jpeg)
    ]
  }
], model: "openai/gpt-4o")

# Content builder
content = Openrouter.Content.build([
  text: "Analyze these files",
  image_url: "https://example.com/chart.png",
  pdf: "https://example.com/report.pdf"
])
```

### Embeddings

```elixir
# Single text
{:ok, [embedding]} = Openrouter.embed(
  "The quick brown fox",
  model: "openai/text-embedding-3-small"
)

# Batch embeddings
texts = ["Hello world", "Goodbye world", "How are you?"]
{:ok, embeddings} = Openrouter.embed(texts, model: "openai/text-embedding-3-small")

# Calculate similarity
similarity = Openrouter.embed_similarity(embedding1, embedding2)
```

### Retry Logic

```elixir
# Automatic retry with exponential backoff
{:ok, response} = Openrouter.Retry.with_retry(
  fn -> Openrouter.chat("Hello", model: "gpt-4") end,
  max_attempts: 5,
  base_delay: 1000,
  retry_on: [:rate_limit, :server_error, :timeout]
)
```

### Telemetry & Observability

```elixir
# Attach default handler
Openrouter.Telemetry.attach_default_handler(level: :info)

# Or custom handler
:telemetry.attach(
  "my-handler",
  [:openrouter, :request, :stop],
  fn _event, measurements, metadata, _config ->
    Logger.info("Request completed",
      duration: measurements.duration,
      model: metadata.model,
      tokens: metadata.tokens
    )
  end,
  nil
)
```

## Examples

The `examples/` directory contains comprehensive examples:

### Core Features
- **`basic_usage.exs`** - Chat, streaming, embeddings
- **`structured_outputs.exs`** - Data extraction with Ecto schemas
- **`production_features.exs`** - Multimodal, retry, telemetry
- **`tool_calling.exs`** - Tool/function calling with agents
- **`run_context.exs`** - Dependency injection patterns
- **`conversation.exs`** - Stateless and stateful conversations

### Advanced Patterns
- **`rag.exs`** - RAG (Retrieval Augmented Generation) with vector search
- **`web_search.exs`** - Web search integration and multi-tool agents
- **`phoenix_liveview.exs`** - Complete Phoenix LiveView chat application
- **`multi_agent.exs`** - Multi-agent collaboration and coordination

Run with:
```bash
mix run examples/basic_usage.exs
mix run examples/rag.exs
mix run examples/phoenix_liveview.exs
```

## Phoenix Integration

### LiveView Streaming

```elixir
defmodule MyAppWeb.ChatLive do
  use Phoenix.LiveView

  def handle_event("send_message", %{"message" => msg}, socket) do
    task = Task.async(fn ->
      Openrouter.chat_stream(msg, model: "gpt-4")
    end)

    {:noreply, assign(socket, task: task, streaming: true)}
  end

  def handle_info({ref, {:ok, stream}}, socket) when socket.assigns.task.ref == ref do
    for chunk <- stream do
      send(self(), {:chunk, chunk})
    end
    {:noreply, socket}
  end

  def handle_info({:chunk, %{content: text}}, socket) do
    # Update UI with new text
    {:noreply, stream_insert(socket, :chunks, %{text: text})}
  end
end
```

### With ConversationServer

```elixir
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

# In your application supervisor
children = [
  {Registry, keys: :unique, name: MyApp.Registry},
  # ... other children
]

# Usage
{:ok, _pid} = MyApp.ChatSession.start_link(user.id)
{:ok, response} = Openrouter.ConversationServer.send_message(
  {:via, Registry, {MyApp.Registry, {MyApp.ChatSession, user.id}}},
  "Hello!"
)
```

## Testing

The library includes 1350+ tests covering:

- **Unit tests**: All modules with comprehensive coverage
- **Integration tests**: Real API calls (with Reqord support for record/replay)

Run tests:

```bash
# Unit tests only (no API key needed)
mix test

# Integration tests (requires API key)
OPENROUTER_API_KEY=your_key mix test --only integration

# Specific test suites
mix test --only chat
mix test --only streaming
mix test --only structured_outputs
mix test --only tool_calling
mix test --only conversation
```

### Using Reqord for Record/Replay

```bash
# Record API interactions
REQORD_MODE=record OPENROUTER_API_KEY=your_key mix test --only integration

# Replay recorded interactions (no API key needed)
REQORD_MODE=replay mix test --only integration
```

## Configuration

```elixir
# config/config.exs
config :openrouter,
  api_key: System.get_env("OPENROUTER_API_KEY"),
  base_url: "https://openrouter.ai/api/v1",
  default_model: "anthropic/claude-3.5-sonnet",
  app_name: "my-app",  # Optional: for OpenRouter tracking
  site_url: "https://myapp.com"  # Optional

# config/runtime.exs (recommended for production)
config :openrouter,
  api_key: System.fetch_env!("OPENROUTER_API_KEY")
```

## Architecture & Design

This library is heavily inspired by [Pydantic AI](https://ai.pydantic.dev/) and adopts many of its best patterns:

- **Dependency Injection via RunContext** - Type-safe context passing
- **Generic Agent Types** - Agents typed over dependencies
- **Structured Outputs** - Validation with automatic retry
- **Progressive Disclosure** - Simple for basic use, powerful for advanced
- **Testing-First** - Easy mocking with behaviors

See [`DESIGN.md`](./DESIGN.md) for the complete design document.

## Development Status

### ✅ Phase 1: Core Foundation - **COMPLETE**
- Core types (Message, Response, Error, Usage)
- HTTP layer with Req
- OpenRouter provider
- Basic streaming
- Configuration & validation

### ✅ Phase 2: Structured Outputs - **COMPLETE**
- Ecto schema integration
- JSON schema generation
- Automatic validation
- Retry with error feedback
- Complex type support

### ✅ Phase 3: Production Features - **COMPLETE**
- Multimodal content (images, video, PDFs)
- Retry logic with exponential backoff
- Comprehensive telemetry
- Content builders
- Production observability

### ✅ Phase 4: Agentic Workflows - **COMPLETE**
- RunContext & dependency injection
- Tool/function calling
- Agent framework with automatic execution
- Conversation management (stateless)
- ConversationServer (stateful GenServer)

### 🚧 Phase 5: Polish & Documentation - **IN PROGRESS**
- Comprehensive documentation
- More examples
- Performance optimization
- Production guides

## Documentation

- **[API Documentation](https://hexdocs.pm/openrouter)** - Full API reference
- **[DESIGN.md](./DESIGN.md)** - Complete design document
- **[PYDANTIC_AI_ANALYSIS.md](./PYDANTIC_AI_ANALYSIS.md)** - Analysis of Pydantic AI
- **[Integration Tests README](./test/integration/README.md)** - Testing guide

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for your changes
4. Ensure all tests pass
5. Submit a pull request

## Roadmap

- [x] More examples (RAG, web search, multi-agent, Phoenix LiveView)
- [ ] Cost tracking and budgeting
- [ ] Token counting utilities
- [ ] Prompt template management
- [ ] Additional persistence backends (Postgres, Mnesia)
- [ ] Performance benchmarks
- [ ] Production deployment guides
- [ ] Prompt caching optimization
- [ ] More model provider support (Ollama, local models)

## License

MIT License - see [LICENSE](LICENSE) for details

## Credits

Inspired by:
- [Pydantic AI](https://ai.pydantic.dev/) - Design patterns and DX
- [Vercel AI SDK](https://sdk.vercel.ai/) - Excellent developer experience
- [FastAPI](https://fastapi.tiangolo.com/) - Progressive disclosure philosophy

Built with:
- [Req](https://hexdocs.pm/req) - Modern HTTP client
- [Ecto](https://hexdocs.pm/ecto) - Schema validation
- [Telemetry](https://hexdocs.pm/telemetry) - Observability

## Support

- **Issues**: [GitHub Issues](https://github.com/yourorg/openrouter-ex/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourorg/openrouter-ex/discussions)
- **OpenRouter**: [OpenRouter Documentation](https://openrouter.ai/docs)
