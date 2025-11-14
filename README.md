# OpenRouter Elixir SDK

A production-ready Elixir SDK for [OpenRouter](https://openrouter.ai/), bringing the FastAPI/Pydantic AI "feeling" to Elixir AI development.

**Status**: ✅ Phase 2 complete! Chat, streaming, embeddings, and **structured outputs with Ecto** are working.

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

## Quick Examples

### Simple Chat

```elixir
# Simple question
{:ok, response} = Openrouter.chat(
  "What is the capital of France?",
  model: "anthropic/claude-sonnet-4-0"
)

IO.puts(response.content)
# => "The capital of France is Paris."
```

### Structured Data Extraction (NEW!)

One of the most powerful features for backend applications - extract structured, validated data:

```elixir
defmodule UserSchema do
  use Openrouter.Schema

  embedded_schema do
    field :name, :string
    field :age, :integer
    field :email, :string
    field :city, :string
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :age, :email, :city])
    |> validate_required([:name, :age])
    |> validate_format(:email, ~r/@/)
  end
end

text = """
John Doe is a 28-year-old software engineer living in San Francisco.
His email is john.doe@example.com.
"""

{:ok, user} = Openrouter.extract(
  text,
  schema: UserSchema,
  model: "openai/gpt-4"
)

# user is a validated UserSchema struct!
IO.puts(user.name)   # => "John Doe"
IO.puts(user.age)    # => 28
IO.puts(user.email)  # => "john.doe@example.com"
```

The library automatically:
- ✅ Generates JSON schema from your Ecto schema
- ✅ Validates the LLM response against your schema
- ✅ Retries with error feedback if validation fails
- ✅ Returns a properly typed Ecto struct

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

**Phase 2 (Structured Outputs) is now complete!**

This is a major milestone - the library now provides production-ready structured data extraction with Ecto integration, automatic validation, and retry logic.

### Phase 1: Core Foundation ✅ **COMPLETE**
- ✅ Library structure established
- ✅ Core types and behaviors (Message, Response, Error, Usage)
- ✅ HTTP layer with Req
- ✅ OpenRouter provider implementation
- ✅ Basic streaming support
- ✅ Configuration & validation
- ✅ Error handling

### Phase 2: Structured Outputs ✅ **COMPLETE**
- ✅ Ecto schema integration for structured data
- ✅ `Openrouter.Schema` module with `use` macro
- ✅ JSON schema generation from Ecto schemas
- ✅ Automatic validation with Ecto changesets
- ✅ Retry logic with error feedback to LLM
- ✅ Support for embedded schemas and complex types
- ✅ Raw JSON schema support (alternative to Ecto)

### Current API (Phases 1 & 2)

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

# Structured data extraction (NEW!)
{:ok, user} = Openrouter.extract(
  "John Doe, age 30, email: john@example.com",
  schema: UserSchema,
  model: "openai/gpt-4"
)
```

### Phase 3: Agentic Workflows (Next)
- [ ] RunContext & dependency injection
- [ ] Tool calling support
- [ ] Agent framework with macros
- [ ] Conversation management
- [ ] ConversationServer (GenServer)

### Phase 4: Production Features
- [ ] Enhanced streaming with backpressure
- [ ] Multimodal content helpers (images, PDFs, video)
- [ ] Advanced retry logic & circuit breakers
- [ ] Rate limiting utilities
- [ ] Enhanced telemetry events
- [ ] Content builder helpers

### Phase 5: Phoenix Integration
- [ ] LiveView helpers
- [ ] Channel integration
- [ ] Oban worker examples
- [ ] Background job patterns

## Contributing

This project is in early development. Design feedback is welcome! Please open an issue or PR.

## License

[License details to be added]

