defmodule Openrouter.RunContext do
  @moduledoc """
  Context passed to tools and dynamic instructions during agent execution.

  Inspired by Pydantic AI's RunContext pattern, this provides type-safe
  dependency injection for agentic workflows.

  ## Generic Over Dependencies

  The RunContext is generic over the dependency type, allowing tools to
  receive typed dependencies (database connections, user context, etc.)
  in a type-safe way.

  ## Structure

  - `deps` - User-provided dependencies (any type)
  - `messages` - Conversation history up to this point
  - `retry_count` - Number of retries for current request
  - `model` - Current model being used
  - `usage` - Token usage information (if available)

  ## Example

      # Define your dependencies
      defmodule SupportDeps do
        defstruct [:customer_id, :db_conn, :user]

        @type t :: %__MODULE__{
          customer_id: integer(),
          db_conn: DBConnection.t(),
          user: User.t()
        }
      end

      # Tool receives RunContext with typed dependencies
      tool = Openrouter.Tool.new(
        :get_customer_balance,
        "Get customer balance from database",
        fn _params, ctx ->
          # ctx.deps is a SupportDeps struct - fully typed!
          balance = MyApp.DB.get_balance(
            ctx.deps.db_conn,
            ctx.deps.customer_id
          )
          {:ok, balance}
        end,
        context_aware: true
      )

      # Run agent with dependencies
      deps = %SupportDeps{
        customer_id: 123,
        db_conn: conn,
        user: current_user
      }

      {:ok, result} = Openrouter.Agent.run(
        "What's my account balance?",
        model: "gpt-4",
        tools: [tool],
        deps: deps
      )

  ## Type Safety

  While Elixir doesn't have compile-time generics like Python's TypeScript,
  using typespecs with your dependency structs provides similar benefits:

      @spec run_with_deps(RunContext.t(SupportDeps.t())) :: {:ok, term()} | {:error, term()}
      def run_with_deps(%RunContext{deps: %SupportDeps{}} = ctx) do
        # Type checker knows ctx.deps is SupportDeps
        customer_id = ctx.deps.customer_id
        # ...
      end
  """

  alias Openrouter.Types.{Message, Usage}

  @type t(deps) :: %__MODULE__{
          deps: deps,
          messages: [Message.t()],
          retry_count: non_neg_integer(),
          model: String.t(),
          usage: Usage.t() | nil
        }

  @type t() :: t(term())

  defstruct deps: nil,
            messages: [],
            retry_count: 0,
            model: nil,
            usage: nil

  @doc """
  Creates a new RunContext.

  ## Options

    * `:deps` - User-provided dependencies (default: nil)
    * `:messages` - Initial message history (default: [])
    * `:retry_count` - Initial retry count (default: 0)
    * `:model` - Model being used (default: nil)
    * `:usage` - Initial usage information (default: nil)

  ## Examples

      iex> ctx = RunContext.new(deps: %{db: conn, user: user})
      iex> ctx.deps
      %{db: conn, user: user}

      iex> ctx = RunContext.new(
      ...>   deps: %MyDeps{user_id: 123},
      ...>   model: "gpt-4",
      ...>   messages: [%{role: :user, content: "Hello"}]
      ...> )
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      deps: Keyword.get(opts, :deps),
      messages: Keyword.get(opts, :messages, []),
      retry_count: Keyword.get(opts, :retry_count, 0),
      model: Keyword.get(opts, :model),
      usage: Keyword.get(opts, :usage)
    }
  end

  @doc """
  Updates the context with new messages.

  Returns a new RunContext with the updated message list.

  ## Examples

      iex> ctx = RunContext.new()
      iex> ctx = RunContext.add_messages(ctx, [
      ...>   %{role: :user, content: "Hello"},
      ...>   %{role: :assistant, content: "Hi!"}
      ...> ])
      iex> length(ctx.messages)
      2
  """
  @spec add_messages(t(), [Message.t() | map()]) :: t()
  def add_messages(%__MODULE__{} = ctx, messages) when is_list(messages) do
    %{ctx | messages: ctx.messages ++ messages}
  end

  @doc """
  Updates the context with a single message.

  ## Examples

      iex> ctx = RunContext.new()
      iex> ctx = RunContext.add_message(ctx, %{role: :user, content: "Hello"})
      iex> length(ctx.messages)
      1
  """
  @spec add_message(t(), Message.t() | map()) :: t()
  def add_message(%__MODULE__{} = ctx, message) do
    add_messages(ctx, [message])
  end

  @doc """
  Increments the retry count.

  Returns a new RunContext with incremented retry_count.

  ## Examples

      iex> ctx = RunContext.new()
      iex> ctx = RunContext.increment_retry(ctx)
      iex> ctx.retry_count
      1
  """
  @spec increment_retry(t()) :: t()
  def increment_retry(%__MODULE__{} = ctx) do
    %{ctx | retry_count: ctx.retry_count + 1}
  end

  @doc """
  Updates the usage information.

  Returns a new RunContext with updated usage stats.

  ## Examples

      iex> ctx = RunContext.new()
      iex> usage = %Usage{prompt_tokens: 10, completion_tokens: 20}
      iex> ctx = RunContext.update_usage(ctx, usage)
      iex> ctx.usage.prompt_tokens
      10
  """
  @spec update_usage(t(), Usage.t() | nil) :: t()
  def update_usage(%__MODULE__{} = ctx, usage) do
    %{ctx | usage: usage}
  end

  @doc """
  Accumulates usage information.

  If the context already has usage info, adds the new usage to it.
  Otherwise, sets the usage to the provided value.

  ## Examples

      iex> ctx = RunContext.new()
      iex> usage1 = %Usage{prompt_tokens: 10, completion_tokens: 20}
      iex> ctx = RunContext.accumulate_usage(ctx, usage1)
      iex> usage2 = %Usage{prompt_tokens: 5, completion_tokens: 10}
      iex> ctx = RunContext.accumulate_usage(ctx, usage2)
      iex> ctx.usage.prompt_tokens
      15
      iex> ctx.usage.completion_tokens
      30
  """
  @spec accumulate_usage(t(), Usage.t() | nil) :: t()
  def accumulate_usage(%__MODULE__{usage: nil} = ctx, usage) do
    %{ctx | usage: usage}
  end

  def accumulate_usage(%__MODULE__{usage: existing} = ctx, new_usage) when not is_nil(new_usage) do
    %{ctx | usage: Usage.add(existing, new_usage)}
  end

  def accumulate_usage(%__MODULE__{} = ctx, nil) do
    ctx
  end

  @doc """
  Updates the model being used.

  Returns a new RunContext with the updated model.

  ## Examples

      iex> ctx = RunContext.new(model: "gpt-3.5-turbo")
      iex> ctx = RunContext.update_model(ctx, "gpt-4")
      iex> ctx.model
      "gpt-4"
  """
  @spec update_model(t(), String.t()) :: t()
  def update_model(%__MODULE__{} = ctx, model) when is_binary(model) do
    %{ctx | model: model}
  end

  @doc """
  Updates the dependencies.

  Returns a new RunContext with the updated dependencies.

  ## Examples

      iex> ctx = RunContext.new(deps: %{count: 0})
      iex> ctx = RunContext.update_deps(ctx, %{count: 1})
      iex> ctx.deps.count
      1
  """
  @spec update_deps(t(deps), deps) :: t(deps) when deps: term()
  def update_deps(%__MODULE__{} = ctx, deps) do
    %{ctx | deps: deps}
  end

  @doc """
  Resets the retry count to 0.

  ## Examples

      iex> ctx = RunContext.new(retry_count: 3)
      iex> ctx = RunContext.reset_retry(ctx)
      iex> ctx.retry_count
      0
  """
  @spec reset_retry(t()) :: t()
  def reset_retry(%__MODULE__{} = ctx) do
    %{ctx | retry_count: 0}
  end

  @doc """
  Checks if the context has dependencies.

  ## Examples

      iex> ctx = RunContext.new()
      iex> RunContext.has_deps?(ctx)
      false

      iex> ctx = RunContext.new(deps: %{db: conn})
      iex> RunContext.has_deps?(ctx)
      true
  """
  @spec has_deps?(t()) :: boolean()
  def has_deps?(%__MODULE__{deps: nil}), do: false
  def has_deps?(%__MODULE__{deps: _}), do: true

  @doc """
  Gets the number of messages in the context.

  ## Examples

      iex> ctx = RunContext.new(messages: [%{role: :user, content: "Hi"}])
      iex> RunContext.message_count(ctx)
      1
  """
  @spec message_count(t()) :: non_neg_integer()
  def message_count(%__MODULE__{messages: messages}) do
    length(messages)
  end

  @doc """
  Gets the last N messages from the context.

  ## Examples

      iex> messages = [
      ...>   %{role: :user, content: "First"},
      ...>   %{role: :assistant, content: "Second"},
      ...>   %{role: :user, content: "Third"}
      ...> ]
      iex> ctx = RunContext.new(messages: messages)
      iex> recent = RunContext.last_messages(ctx, 2)
      iex> length(recent)
      2
      iex> List.last(recent).content
      "Third"
  """
  @spec last_messages(t(), pos_integer()) :: [Message.t()]
  def last_messages(%__MODULE__{messages: messages}, n) when is_integer(n) and n > 0 do
    messages |> Enum.take(-n)
  end

  @doc """
  Converts the context to a map for inspection or serialization.

  ## Examples

      iex> ctx = RunContext.new(
      ...>   deps: %{user_id: 123},
      ...>   model: "gpt-4",
      ...>   retry_count: 1
      ...> )
      iex> map = RunContext.to_map(ctx)
      iex> map.model
      "gpt-4"
      iex> map.retry_count
      1
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = ctx) do
    %{
      deps: ctx.deps,
      messages: ctx.messages,
      retry_count: ctx.retry_count,
      model: ctx.model,
      usage: ctx.usage
    }
  end
end
