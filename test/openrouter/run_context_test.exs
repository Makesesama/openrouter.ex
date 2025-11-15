defmodule Openrouter.RunContextTest do
  use ExUnit.Case, async: true

  alias Openrouter.RunContext
  alias Openrouter.Types.{Message, Usage}

  describe "RunContext.new/1" do
    test "creates a new context with defaults" do
      ctx = RunContext.new()

      assert ctx.deps == nil
      assert ctx.messages == []
      assert ctx.retry_count == 0
      assert ctx.model == nil
      assert ctx.usage == nil
    end

    test "creates a context with custom options" do
      deps = %{user_id: 123, db: :conn}
      messages = [%{role: :user, content: "Hello"}]

      ctx =
        RunContext.new(
          deps: deps,
          messages: messages,
          model: "gpt-4",
          retry_count: 2
        )

      assert ctx.deps == deps
      assert ctx.messages == messages
      assert ctx.model == "gpt-4"
      assert ctx.retry_count == 2
    end

    test "creates a context with usage information" do
      usage = %Usage{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}
      ctx = RunContext.new(usage: usage)

      assert ctx.usage == usage
    end
  end

  describe "RunContext.add_messages/2" do
    test "adds multiple messages to empty context" do
      ctx = RunContext.new()

      messages = [
        %{role: :user, content: "First"},
        %{role: :assistant, content: "Second"}
      ]

      ctx = RunContext.add_messages(ctx, messages)

      assert length(ctx.messages) == 2
      assert Enum.at(ctx.messages, 0).content == "First"
      assert Enum.at(ctx.messages, 1).content == "Second"
    end

    test "appends messages to existing ones" do
      initial_messages = [%{role: :user, content: "Existing"}]
      ctx = RunContext.new(messages: initial_messages)

      new_messages = [%{role: :assistant, content: "New"}]
      ctx = RunContext.add_messages(ctx, new_messages)

      assert length(ctx.messages) == 2
      assert Enum.at(ctx.messages, 0).content == "Existing"
      assert Enum.at(ctx.messages, 1).content == "New"
    end

    test "handles empty message list" do
      ctx = RunContext.new()
      ctx = RunContext.add_messages(ctx, [])

      assert ctx.messages == []
    end
  end

  describe "RunContext.add_message/2" do
    test "adds a single message" do
      ctx = RunContext.new()
      ctx = RunContext.add_message(ctx, %{role: :user, content: "Hello"})

      assert length(ctx.messages) == 1
      assert Enum.at(ctx.messages, 0).content == "Hello"
    end

    test "adds message to existing list" do
      ctx = RunContext.new(messages: [%{role: :user, content: "First"}])
      ctx = RunContext.add_message(ctx, %{role: :assistant, content: "Second"})

      assert length(ctx.messages) == 2
    end
  end

  describe "RunContext.increment_retry/1" do
    test "increments retry count from 0" do
      ctx = RunContext.new()
      ctx = RunContext.increment_retry(ctx)

      assert ctx.retry_count == 1
    end

    test "increments retry count multiple times" do
      ctx = RunContext.new()

      ctx =
        ctx
        |> RunContext.increment_retry()
        |> RunContext.increment_retry()
        |> RunContext.increment_retry()

      assert ctx.retry_count == 3
    end

    test "increments from existing count" do
      ctx = RunContext.new(retry_count: 5)
      ctx = RunContext.increment_retry(ctx)

      assert ctx.retry_count == 6
    end
  end

  describe "RunContext.update_usage/2" do
    test "sets usage when nil" do
      ctx = RunContext.new()
      usage = %Usage{prompt_tokens: 100, completion_tokens: 50, total_tokens: 150}

      ctx = RunContext.update_usage(ctx, usage)

      assert ctx.usage == usage
      assert ctx.usage.prompt_tokens == 100
    end

    test "replaces existing usage" do
      old_usage = %Usage{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}
      ctx = RunContext.new(usage: old_usage)

      new_usage = %Usage{prompt_tokens: 100, completion_tokens: 50, total_tokens: 150}
      ctx = RunContext.update_usage(ctx, new_usage)

      assert ctx.usage == new_usage
      assert ctx.usage.prompt_tokens == 100
    end

    test "can set usage to nil" do
      usage = %Usage{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}
      ctx = RunContext.new(usage: usage)

      ctx = RunContext.update_usage(ctx, nil)

      assert ctx.usage == nil
    end
  end

  describe "RunContext.accumulate_usage/2" do
    test "sets usage when context has no usage" do
      ctx = RunContext.new()
      usage = %Usage{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}

      ctx = RunContext.accumulate_usage(ctx, usage)

      assert ctx.usage == usage
    end

    test "adds to existing usage" do
      initial = %Usage{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}
      ctx = RunContext.new(usage: initial)

      additional = %Usage{prompt_tokens: 5, completion_tokens: 10, total_tokens: 15}
      ctx = RunContext.accumulate_usage(ctx, additional)

      assert ctx.usage.prompt_tokens == 15
      assert ctx.usage.completion_tokens == 30
      assert ctx.usage.total_tokens == 45
    end

    test "handles nil new usage gracefully" do
      usage = %Usage{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}
      ctx = RunContext.new(usage: usage)

      ctx = RunContext.accumulate_usage(ctx, nil)

      # Usage should remain unchanged
      assert ctx.usage == usage
    end

    test "accumulates usage multiple times" do
      ctx = RunContext.new()

      usage1 = %Usage{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
      usage2 = %Usage{prompt_tokens: 20, completion_tokens: 10, total_tokens: 30}
      usage3 = %Usage{prompt_tokens: 5, completion_tokens: 15, total_tokens: 20}

      ctx =
        ctx
        |> RunContext.accumulate_usage(usage1)
        |> RunContext.accumulate_usage(usage2)
        |> RunContext.accumulate_usage(usage3)

      assert ctx.usage.prompt_tokens == 35
      assert ctx.usage.completion_tokens == 30
      assert ctx.usage.total_tokens == 65
    end
  end

  describe "RunContext.update_model/2" do
    test "sets model when nil" do
      ctx = RunContext.new()
      ctx = RunContext.update_model(ctx, "gpt-4")

      assert ctx.model == "gpt-4"
    end

    test "updates existing model" do
      ctx = RunContext.new(model: "gpt-3.5-turbo")
      ctx = RunContext.update_model(ctx, "gpt-4")

      assert ctx.model == "gpt-4"
    end
  end

  describe "RunContext.update_deps/2" do
    test "sets dependencies when nil" do
      ctx = RunContext.new()
      deps = %{user_id: 123, db: :conn}

      ctx = RunContext.update_deps(ctx, deps)

      assert ctx.deps == deps
    end

    test "updates existing dependencies" do
      old_deps = %{user_id: 123}
      ctx = RunContext.new(deps: old_deps)

      new_deps = %{user_id: 456, role: :admin}
      ctx = RunContext.update_deps(ctx, new_deps)

      assert ctx.deps == new_deps
      assert ctx.deps.user_id == 456
    end
  end

  describe "RunContext.reset_retry/1" do
    test "resets retry count to 0" do
      ctx = RunContext.new(retry_count: 5)
      ctx = RunContext.reset_retry(ctx)

      assert ctx.retry_count == 0
    end

    test "works when already 0" do
      ctx = RunContext.new()
      ctx = RunContext.reset_retry(ctx)

      assert ctx.retry_count == 0
    end
  end

  describe "RunContext.has_deps?/1" do
    test "returns false when deps is nil" do
      ctx = RunContext.new()

      refute RunContext.has_deps?(ctx)
    end

    test "returns true when deps is set" do
      ctx = RunContext.new(deps: %{user_id: 123})

      assert RunContext.has_deps?(ctx)
    end

    test "returns true even for empty map deps" do
      ctx = RunContext.new(deps: %{})

      assert RunContext.has_deps?(ctx)
    end
  end

  describe "RunContext.message_count/1" do
    test "returns 0 for empty messages" do
      ctx = RunContext.new()

      assert RunContext.message_count(ctx) == 0
    end

    test "returns correct count for messages" do
      messages = [
        %{role: :user, content: "First"},
        %{role: :assistant, content: "Second"},
        %{role: :user, content: "Third"}
      ]

      ctx = RunContext.new(messages: messages)

      assert RunContext.message_count(ctx) == 3
    end

    test "updates after adding messages" do
      ctx = RunContext.new()
      assert RunContext.message_count(ctx) == 0

      ctx = RunContext.add_message(ctx, %{role: :user, content: "Hello"})
      assert RunContext.message_count(ctx) == 1

      ctx = RunContext.add_message(ctx, %{role: :assistant, content: "Hi"})
      assert RunContext.message_count(ctx) == 2
    end
  end

  describe "RunContext.last_messages/2" do
    test "returns empty list when no messages" do
      ctx = RunContext.new()

      assert RunContext.last_messages(ctx, 5) == []
    end

    test "returns last N messages" do
      messages = [
        %{role: :user, content: "First"},
        %{role: :assistant, content: "Second"},
        %{role: :user, content: "Third"},
        %{role: :assistant, content: "Fourth"}
      ]

      ctx = RunContext.new(messages: messages)

      last_two = RunContext.last_messages(ctx, 2)

      assert length(last_two) == 2
      assert Enum.at(last_two, 0).content == "Third"
      assert Enum.at(last_two, 1).content == "Fourth"
    end

    test "returns all messages when N is larger than message count" do
      messages = [
        %{role: :user, content: "First"},
        %{role: :assistant, content: "Second"}
      ]

      ctx = RunContext.new(messages: messages)

      last = RunContext.last_messages(ctx, 10)

      assert length(last) == 2
    end

    test "returns single message when N is 1" do
      messages = [
        %{role: :user, content: "First"},
        %{role: :assistant, content: "Second"}
      ]

      ctx = RunContext.new(messages: messages)

      last = RunContext.last_messages(ctx, 1)

      assert length(last) == 1
      assert Enum.at(last, 0).content == "Second"
    end
  end

  describe "RunContext.to_map/1" do
    test "converts context to map" do
      deps = %{user_id: 123}
      messages = [%{role: :user, content: "Hello"}]
      usage = %Usage{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}

      ctx =
        RunContext.new(
          deps: deps,
          messages: messages,
          model: "gpt-4",
          retry_count: 2,
          usage: usage
        )

      map = RunContext.to_map(ctx)

      assert is_map(map)
      assert map.deps == deps
      assert map.messages == messages
      assert map.model == "gpt-4"
      assert map.retry_count == 2
      assert map.usage == usage
    end

    test "converts empty context to map" do
      ctx = RunContext.new()
      map = RunContext.to_map(ctx)

      assert is_map(map)
      assert map.deps == nil
      assert map.messages == []
      assert map.model == nil
      assert map.retry_count == 0
      assert map.usage == nil
    end

    test "map has all expected keys" do
      ctx = RunContext.new()
      map = RunContext.to_map(ctx)

      assert Map.has_key?(map, :deps)
      assert Map.has_key?(map, :messages)
      assert Map.has_key?(map, :model)
      assert Map.has_key?(map, :retry_count)
      assert Map.has_key?(map, :usage)
    end
  end

  describe "RunContext integration" do
    test "supports full workflow" do
      # Start with empty context
      ctx = RunContext.new()

      # Add dependencies
      deps = %{user_id: 123, api_key: "secret"}
      ctx = RunContext.update_deps(ctx, deps)

      # Set model
      ctx = RunContext.update_model(ctx, "gpt-4")

      # Add some messages
      ctx =
        ctx
        |> RunContext.add_message(%{role: :user, content: "Hello"})
        |> RunContext.add_message(%{role: :assistant, content: "Hi there!"})

      # Add usage
      usage1 = %Usage{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
      ctx = RunContext.accumulate_usage(ctx, usage1)

      # Simulate another round
      ctx = RunContext.increment_retry(ctx)

      usage2 = %Usage{prompt_tokens: 20, completion_tokens: 15, total_tokens: 35}
      ctx = RunContext.accumulate_usage(ctx, usage2)

      # Verify final state
      assert ctx.deps.user_id == 123
      assert ctx.model == "gpt-4"
      assert RunContext.message_count(ctx) == 2
      assert ctx.retry_count == 1
      assert ctx.usage.total_tokens == 50
    end

    test "supports immutable updates" do
      original = RunContext.new(model: "gpt-3.5-turbo", retry_count: 0)

      updated = RunContext.increment_retry(original)

      # Original is unchanged
      assert original.retry_count == 0
      # Updated has new value
      assert updated.retry_count == 1
    end
  end

  describe "RunContext with custom dependency types" do
    defmodule TestDeps do
      defstruct [:user_id, :session_token, :role]

      @type t :: %__MODULE__{
              user_id: integer(),
              session_token: String.t(),
              role: atom()
            }
    end

    test "works with custom struct dependencies" do
      deps = %TestDeps{
        user_id: 456,
        session_token: "abc123",
        role: :admin
      }

      ctx = RunContext.new(deps: deps)

      assert ctx.deps.user_id == 456
      assert ctx.deps.session_token == "abc123"
      assert ctx.deps.role == :admin
    end

    test "maintains type through updates" do
      deps = %TestDeps{user_id: 123, session_token: "xyz", role: :user}
      ctx = RunContext.new(deps: deps)

      # Add messages
      ctx = RunContext.add_message(ctx, %{role: :user, content: "Test"})

      # Dependencies are preserved with correct type
      assert %TestDeps{} = ctx.deps
      assert ctx.deps.user_id == 123
    end
  end
end
