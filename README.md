# OpenRouter Elixir SDK

A production-ready Elixir SDK for [OpenRouter](https://openrouter.ai/), bringing the FastAPI/Pydantic AI "feeling" to Elixir AI development.

**Status**: ✅ Phase 1 (Core Foundation) complete! Basic chat, streaming, and embeddings are working.

## Why OpenRouter?

[OpenRouter](https://openrouter.ai/) provides unified access to **all major AI models** through a single API:
- OpenAI (GPT-4, GPT-3.5, o1, etc.)
- Anthropic (Claude 3.5 Sonnet, Claude 4, etc.)
- Google (Gemini 2.0, Gemini Flash, etc.)
- Meta (Llama 3.3, etc.)
- And 200+ more models

Instead of building separate clients for each provider, this SDK focuses on making the best possible OpenRouter client.

## Features (Planned)

🎯 **Backend-First**
- Production-ready with OTP supervision
- GenServer-based stateful conversations
- Connection pooling via Req/Finch
- Built-in telemetry and observability

🤖 **Agentic Workflows**
- Type-safe dependency injection (inspired by Pydantic AI)
- Tool/function calling support
- Automatic tool execution loops
- Human-in-the-loop approvals

🔒 **Type Safety**
- Structured outputs with Ecto schema validation
- Automatic retry on validation failures
- Compile-time safety with typespecs

🔌 **Phoenix Integration**
- LiveView streaming support
- Phoenix Channels integration
- Oban background job examples
- Context-based architecture

## Design Philosophy

This SDK is heavily inspired by [Pydantic AI](https://ai.pydantic.dev/) and adopts many of its best patterns:

1. **Dependency Injection via RunContext** - Type-safe context passing to tools and instructions
2. **Generic Agent Types** - Agents typed over dependencies and output types
3. **Structured Outputs** - Automatic validation and retry using Ecto schemas
4. **Toolsets** - Reusable, composable tool collections
5. **Testing-First** - Easy mocking with test providers

See [`DESIGN.md`](./DESIGN.md) for the complete design document and [`PYDANTIC_AI_ANALYSIS.md`](./PYDANTIC_AI_ANALYSIS.md) for our analysis of Pydantic AI.

## Quick Example (Planned API)

```elixir
defmodule MyApp.SupportAgent do
  use Openrouter.Agent,
    model: "anthropic/claude-sonnet-4-0",
    deps_type: SupportDeps

  @instruction
  def system_prompt(ctx) do
    "You are helping customer ##{ctx.deps.customer_id}"
  end

  @tool
  def get_balance(ctx, %{include_pending: pending}) do
    Database.get_balance(ctx.deps.db, ctx.deps.customer_id, pending)
  end
end

# Use the agent
deps = %SupportDeps{customer_id: 123, db: db_conn}
{:ok, result} = MyApp.SupportAgent.run("What's my balance?", deps: deps)
```

## Installation (When Released)

```elixir
def deps do
  [
    {:openrouter, "~> 0.1.0"}
  ]
end
```

## Documentation

- **[DESIGN.md](./DESIGN.md)** - Complete design document
- **[PYDANTIC_AI_ANALYSIS.md](./PYDANTIC_AI_ANALYSIS.md)** - Analysis of Pydantic AI patterns

## Development Status

Phase 1 (Core Foundation) is now complete! Basic chat, streaming, and embeddings are implemented.

### Phase 1: Core Foundation ✅ **COMPLETE**
- ✅ Library structure established
- ✅ Core types and behaviors (Message, Response, Error, Usage)
- ✅ HTTP layer with Req
- ✅ OpenRouter provider implementation
- ✅ Basic streaming support
- ✅ Configuration & validation
- ✅ Error handling

### Current API (Phase 1)

```elixir
# Simple chat
{:ok, response} = Openrouter.chat("What is the capital of France?",
  model: "anthropic/claude-sonnet-4-0")

# With conversation history
messages = [
  %{role: :system, content: "You are a helpful assistant"},
  %{role: :user, content: "Hello!"}
]
{:ok, response} = Openrouter.chat(messages, model: "openai/gpt-4")

# Streaming
{:ok, stream} = Openrouter.chat_stream("Tell me a story", model: "gpt-4")
stream |> Stream.each(fn %{content: text} -> IO.write(text) end) |> Stream.run()

# Embeddings
{:ok, [embedding]} = Openrouter.embed("Hello world", model: "text-embedding-3-small")
```

### Phase 2: Production Readiness (Next)
- [ ] Enhanced streaming with backpressure
- [ ] Multimodal content helpers (images, PDFs, video)
- [ ] Retry logic & fault tolerance
- [ ] Rate limiting utilities
- [ ] Enhanced telemetry

### Phase 3: Agentic Workflows
- [ ] RunContext & dependency injection
- [ ] Tool calling support
- [ ] Agent framework with macros
- [ ] Conversation management
- [ ] ConversationServer (GenServer)

### Phase 4: Phoenix Integration
- [ ] LiveView helpers
- [ ] Channel integration
- [ ] Oban worker examples
- [ ] Structured outputs with Ecto

## Contributing

This project is in early development. Design feedback is welcome! Please open an issue or PR.

## License

[License details to be added]

