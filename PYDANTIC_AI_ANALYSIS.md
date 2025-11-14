# Pydantic AI Analysis: What Makes It Excellent

## Overview

Pydantic AI is a "GenAI Agent Framework, the Pydantic way" - designed to bring the FastAPI feeling to AI development. After analyzing the codebase, here are the key patterns and design decisions we should adopt for our Elixir SDK.

## 1. Dependency Injection Pattern (RunContext)

**What they do:**

```python
@dataclass
class SupportDependencies:
    customer_id: int
    db: DatabaseConn

agent = Agent('openai:gpt-5', deps_type=SupportDependencies)

@agent.tool
async def customer_balance(
    ctx: RunContext[SupportDependencies],  # Dependencies injected here
    include_pending: bool
) -> float:
    return await ctx.deps.db.customer_balance(
        id=ctx.deps.customer_id,
        include_pending=include_pending
    )
```

**Why it's brilliant:**
- Type-safe dependency injection throughout tools and instructions
- Clear separation of context (deps) from tool parameters
- Makes testing trivial - just pass different deps
- Allows dynamic instructions based on context

**Elixir equivalent:**

```elixir
defmodule SupportDeps do
  defstruct [:customer_id, :db]
end

agent = AIKit.Agent.new(
  model: "gpt-4",
  deps_type: SupportDeps
)

AIKit.Agent.tool(agent, :customer_balance, fn ctx, %{include_pending: pending} ->
  # ctx.deps is a SupportDeps struct
  ctx.deps.db.customer_balance(ctx.deps.customer_id, pending)
end)
```

## 2. Generic Type Parameters for Type Safety

**What they do:**

```python
# Agent is generic over dependencies AND output type
agent: Agent[SupportDependencies, SupportOutput] = Agent(
    'openai:gpt-5',
    deps_type=SupportDependencies,
    output_type=SupportOutput  # Guaranteed structured output
)

result = await agent.run('Help me', deps=deps)
# result.output is typed as SupportOutput
print(result.output.support_advice)  # Type checked!
```

**Why it's brilliant:**
- Compile-time guarantees about what an agent returns
- IDE autocomplete works perfectly
- "If it compiles, it works" feeling
- Clear contracts for agent capabilities

**Elixir equivalent using typespecs:**

```elixir
@type agent(deps, output) :: %AIKit.Agent{
  deps_type: module(),
  output_type: module()
}

@spec run(agent(deps, output), String.t(), deps) ::
  {:ok, %{output: output}} | {:error, term()}
  when deps: struct(), output: struct()
```

## 3. Decorator Pattern for Tools & Instructions

**What they do:**

```python
@agent.tool
async def get_weather(ctx: RunContext[Deps], location: str) -> str:
    """Get weather for a location."""  # Docstring becomes tool description
    return await weather_api.fetch(location)

@agent.instructions
async def dynamic_instruction(ctx: RunContext[Deps]) -> str:
    name = await ctx.deps.db.get_name(ctx.deps.user_id)
    return f"The user's name is {name}"
```

**Why it's brilliant:**
- Clean, declarative API
- Docstrings automatically become LLM tool descriptions
- Easy to add tools incrementally
- Dynamic instructions with full context access

**Elixir equivalent:**

```elixir
# Using module attributes or a macro
defmodule MyAgent do
  use AIKit.Agent, model: "gpt-4", deps_type: Deps

  @tool [
    name: :get_weather,
    description: "Get weather for a location",
    params: [location: :string]
  ]
  def get_weather(ctx, %{location: location}) do
    WeatherAPI.fetch(location)
  end

  @instruction
  def dynamic_instruction(ctx) do
    name = ctx.deps.db.get_name(ctx.deps.user_id)
    "The user's name is #{name}"
  end
end
```

## 4. Unified Model Interface with Provider Prefixes

**What they do:**

```python
# Simple string format: "provider:model"
agent = Agent('openai:gpt-4o')
agent = Agent('anthropic:claude-sonnet-4-0')
agent = Agent('google-gla:gemini-2.5-flash')
agent = Agent('groq:llama-3.3-70b-versatile')

# Or runtime override
result = await agent.run('Hello', model='openai:gpt-4')
```

**Why it's brilliant:**
- One unified interface for all providers
- Easy to switch providers
- Model name encodes provider (no separate config needed)
- Runtime model selection for A/B testing

**Elixir equivalent:**

```elixir
# Parse "provider:model" format
agent = AIKit.new("openai:gpt-4")
agent = AIKit.new("anthropic:claude-sonnet-4-0")

# Runtime override
AIKit.chat(agent, "Hello", model: "anthropic:claude-3.5-sonnet")
```

## 5. Structured Output with Automatic Retry

**What they do:**

```python
class RecipeOutput(BaseModel):
    name: str
    ingredients: list[str]
    steps: list[str]

agent = Agent(
    'openai:gpt-4',
    output_type=RecipeOutput
)

result = await agent.run('Give me a cookie recipe')
# result.output is guaranteed to be a valid RecipeOutput
# If LLM returns invalid data, agent automatically retries
```

**Why it's brilliant:**
- Pydantic validation ensures correct schema
- Automatic retry on validation failure
- LLM gets validation errors and fixes them
- Zero boilerplate for structured data

**Elixir equivalent:**

```elixir
defmodule RecipeOutput do
  use Ecto.Schema

  embedded_schema do
    field :name, :string
    field :ingredients, {:array, :string}
    field :steps, {:array, :string}
  end
end

agent = AIKit.new(
  model: "gpt-4",
  output_type: RecipeOutput
)

{:ok, result} = AIKit.run(agent, "Give me a cookie recipe")
# result.output is a validated RecipeOutput struct
```

## 6. Streaming with Structured Events

**What they do:**

```python
async with agent.run_stream('Write a story') as result:
    async for message in result.stream_output():
        print(message, end='')

    # Still get usage info at the end
    print(result.usage())
```

**Why it's brilliant:**
- Stream text incrementally
- Get usage/metadata when done
- Clean async context manager API
- Can stream structured outputs too!

**Elixir equivalent:**

```elixir
{:ok, stream} = AIKit.stream(agent, "Write a story")

stream
|> Stream.each(fn chunk -> IO.write(chunk.content) end)
|> Stream.run()

# Or collect all events
events = Enum.to_list(stream)
usage = List.last(events).usage
```

## 7. Built-in Telemetry & Observability

**What they do:**

```python
import logfire

logfire.configure()
logfire.instrument_pydantic_ai()  # Automatic instrumentation

# Now every agent run is automatically traced
agent = Agent('openai:gpt-4')
result = await agent.run('Hello')  # Automatically logged to Logfire
```

**Why it's brilliant:**
- OpenTelemetry-based observability
- Zero-code instrumentation
- Tracks costs, latency, errors
- Works with any OTel backend

**Elixir equivalent:**

```elixir
# In application.ex
:telemetry.attach_many(
  "aikit-telemetry",
  [
    [:aikit, :request, :start],
    [:aikit, :request, :stop],
    [:aikit, :request, :exception]
  ],
  &MyApp.Telemetry.handle_event/4,
  nil
)

# Automatically emits events
AIKit.chat("Hello")  # Emits telemetry events
```

## 8. Model Profiles for Provider Quirks

**What they do:**

```python
# Each provider has a "profile" defining capabilities
class ModelProfile:
    default_structured_output_mode: 'native' | 'tool' | 'prompted'
    supports_streaming: bool
    supports_tool_calling: bool
    json_schema_transformer: Callable  # Handle vendor-specific schema differences
    max_tokens_limit: int
```

**Why it's brilliant:**
- Centralizes provider differences
- Automatic adaptation to model capabilities
- Falls back gracefully
- Users don't need to know provider quirks

**Elixir equivalent:**

```elixir
defmodule AIKit.Provider.Profile do
  defstruct [
    :default_structured_output_mode,
    :supports_streaming,
    :supports_tool_calling,
    :max_tokens_limit
  ]
end

# Each provider defines its profile
defmodule AIKit.Providers.OpenRouter do
  def profile do
    %Profile{
      default_structured_output_mode: :native,
      supports_streaming: true,
      supports_tool_calling: true
    }
  end
end
```

## 9. Toolsets for Modularity

**What they do:**

```python
# Built-in toolsets
from pydantic_ai import WebSearchTool, CodeExecutionTool

agent = Agent(
    'openai:gpt-4',
    builtin_tools=[
        WebSearchTool(),
        CodeExecutionTool()
    ]
)

# Custom toolsets
class DatabaseToolset(AbstractToolset):
    def __init__(self, db: DatabaseConn):
        self.db = db

    def get_tools(self) -> list[Tool]:
        return [...]

agent.add_toolset(DatabaseToolset(db))
```

**Why it's brilliant:**
- Reusable tool collections
- Composable - mix and match toolsets
- Built-in tools for common tasks
- Easy to package and share

**Elixir equivalent:**

```elixir
defmodule AIKit.Toolsets.WebSearch do
  use AIKit.Toolset

  def tools(_ctx) do
    [
      tool(:web_search, "Search the web", fn ctx, %{query: q} ->
        # Implementation
      end)
    ]
  end
end

agent = AIKit.new(
  model: "gpt-4",
  toolsets: [
    AIKit.Toolsets.WebSearch,
    AIKit.Toolsets.Database.new(db)
  ]
)
```

## 10. Human-in-the-Loop Tool Approval

**What they do:**

```python
@agent.tool
async def delete_database(ctx: RunContext[Deps]) -> str:
    """Delete the entire database."""
    raise CallDeferred  # Requires approval before executing

# Later, handle deferred calls
deferred = result.deferred_tool_calls()
# User approves/denies
result = await agent.run_deferred(deferred, approved=[...])
```

**Why it's brilliant:**
- Safety for dangerous operations
- User control over risky actions
- Audit trail of approvals
- Works seamlessly with agent loop

**Elixir equivalent:**

```elixir
defmodule MyAgent do
  use AIKit.Agent

  @tool [name: :delete_database, requires_approval: true]
  def delete_database(_ctx, _params) do
    # Only runs if approved
    Database.delete_all()
  end
end

{:ok, result} = AIKit.run(agent, "Clean up the database")

case result do
  %{pending_approvals: [approval | _]} ->
    # Ask user for approval
    if user_approves?() do
      AIKit.approve(agent, result, [approval.id])
    end
  _ ->
    # No approvals needed
    result.output
end
```

## 11. Message History Management

**What they do:**

```python
# Automatic message history preservation
result1 = await agent.run('Hello')
result2 = await agent.run('What did I just say?', message_history=result1.messages())

# Or use message history as a list
messages = [
    ModelRequest(...),
    ModelResponse(...),
    ModelRequest(...)
]
result = await agent.run('Continue', message_history=messages)
```

**Why it's brilliant:**
- Explicit message history passing
- No hidden state
- Easy to persist/resume conversations
- Full control over context

**Elixir equivalent:**

```elixir
{:ok, result1} = AIKit.run(agent, "Hello")
{:ok, result2} = AIKit.run(agent, "What did I just say?",
  message_history: result1.messages
)

# Or manage manually
messages = [
  %Message{role: :user, content: "Hello"},
  %Message{role: :assistant, content: "Hi!"}
]

{:ok, result} = AIKit.run(agent, "Continue", messages: messages)
```

## 12. Testing Utilities

**What they do:**

```python
from pydantic_ai.models.test import TestModel

# Deterministic testing
test_model = TestModel()
agent = Agent(test_model)

# Define expected responses
test_model.add_response('Hello world!')

result = agent.run_sync('Any prompt')
assert result.output == 'Hello world!'

# Can also record/replay real API calls
```

**Why it's brilliant:**
- No API calls in tests
- Deterministic results
- Fast test execution
- Record/replay for integration tests

**Elixir equivalent:**

```elixir
defmodule AIKit.TestModel do
  @behaviour AIKit.Provider

  def set_response(response) do
    # Store in process dictionary or ETS
  end

  def chat(_config, _params) do
    {:ok, get_stored_response()}
  end
end

# In tests
test "agent responds correctly" do
  AIKit.TestModel.set_response("Hello world!")

  agent = AIKit.new(provider: AIKit.TestModel)
  {:ok, result} = AIKit.run(agent, "Any prompt")

  assert result.output == "Hello world!"
end
```

## Key Takeaways for Our Elixir SDK

### Must Have (Core Features)

1. **Dependency Injection via Context** - RunContext pattern with typed dependencies
2. **Generic Agent Types** - Agent generic over deps and output types
3. **Unified Provider Interface** - "provider:model" string format
4. **Structured Output with Validation** - Ecto schema integration with auto-retry
5. **Streaming Support** - First-class streaming with events
6. **Telemetry Integration** - Built-in observability
7. **Tool/Function Calling** - Clean decorator/macro pattern
8. **Testing Utilities** - Mock provider for tests

### Should Have (Enhanced UX)

1. **Model Profiles** - Abstract provider differences
2. **Toolsets** - Reusable, composable tool collections
3. **Dynamic Instructions** - Context-aware system prompts
4. **Message History Management** - Explicit, functional approach
5. **Usage Tracking** - Token/cost tracking
6. **Retry Logic** - Automatic retry on validation failures

### Nice to Have (Advanced Features)

1. **Human-in-the-Loop** - Tool approval system
2. **Durable Execution** - Persist and resume long-running agents
3. **Graph-based Workflows** - State machines for complex flows
4. **Built-in Toolsets** - Web search, code execution, etc.
5. **MCP Integration** - Model Context Protocol support
6. **A2A Protocol** - Agent-to-Agent communication

## Architecture Patterns to Adopt

### 1. Behavior-Based Model Interface

```elixir
defmodule AIKit.Provider do
  @callback request(config, messages, params) ::
    {:ok, response} | {:error, term()}

  @callback request_stream(config, messages, params) ::
    Enumerable.t()

  @callback name() :: String.t()
end
```

### 2. Dataclass-Style Structs

```elixir
defmodule AIKit.Agent do
  @enforce_keys [:model]
  defstruct [
    :model,
    :deps_type,
    :output_type,
    :instructions,
    :tools,
    :toolsets,
    :settings
  ]
end
```

### 3. Message-Based Protocol

```elixir
defmodule AIKit.Message do
  @type t ::
    %__MODULE__.Request{} |
    %__MODULE__.Response{}
end

defmodule AIKit.Message.Request do
  defstruct [:role, :parts, :timestamp]
end

defmodule AIKit.Message.Response do
  defstruct [:role, :parts, :usage, :finish_reason]
end
```

### 4. Result Objects with Rich Metadata

```elixir
defmodule AIKit.Result do
  defstruct [
    :output,        # The actual response/structured data
    :messages,      # Full message history
    :usage,         # Token usage
    :model,         # Model used
    :timestamp,     # When completed
    :cost           # Estimated cost
  ]
end
```

## API Design Comparison

### Pydantic AI
```python
agent = Agent(
    'openai:gpt-4',
    deps_type=Deps,
    output_type=Output,
    instructions='Be helpful'
)

@agent.tool
async def my_tool(ctx: RunContext[Deps], arg: str) -> str:
    return await ctx.deps.db.fetch(arg)

result = await agent.run('Hello', deps=Deps(...))
```

### Our Elixir SDK (Proposed)
```elixir
agent = AIKit.Agent.new(
  model: "openai:gpt-4",
  deps_type: Deps,
  output_type: Output,
  instructions: "Be helpful"
)

agent = AIKit.Agent.tool(agent, :my_tool, fn ctx, %{arg: arg} ->
  ctx.deps.db.fetch(arg)
end)

{:ok, result} = AIKit.Agent.run(agent, "Hello", deps: %Deps{})
```

Or with a macro:

```elixir
defmodule MyAgent do
  use AIKit.Agent,
    model: "openai:gpt-4",
    deps_type: Deps,
    output_type: Output,
    instructions: "Be helpful"

  @tool
  def my_tool(ctx, %{arg: arg}) do
    ctx.deps.db.fetch(arg)
  end
end

{:ok, result} = MyAgent.run("Hello", deps: %Deps{})
```

## Summary

Pydantic AI's excellence comes from:

1. **Type safety everywhere** - Generics, validation, IDE support
2. **Dependency injection** - Clean, testable, composable
3. **Unified interface** - One API for all providers
4. **Automatic validation & retry** - LLMs fix their own mistakes
5. **Built-in observability** - Production-ready from day one
6. **Functional composition** - Tools, toolsets, instructions compose cleanly
7. **Human-in-the-loop** - Safety for critical operations
8. **Testing-first** - Easy mocking and deterministic tests

Our Elixir SDK should adopt these patterns while leveraging Elixir's strengths:
- Processes for stateful conversations
- OTP for supervision and fault tolerance
- Pattern matching for elegant message handling
- Streams for lazy evaluation
- Protocols for polymorphism
