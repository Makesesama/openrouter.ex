defmodule Openrouter.Integration.RunContextTest do
  use Reqord.Case

  @moduletag :integration
  @moduletag :run_context

  alias Openrouter.{RunContext, Tool}

  describe "RunContext with context-aware tools" do
    defmodule SimpleDeps do
      defstruct [:user_id, :api_key]
    end

    @tag :integration
    test "context-aware tool receives RunContext with dependencies" do
      deps = %SimpleDeps{user_id: 123, api_key: "secret"}

      tool =
        Tool.new(
          :get_user_id,
          "Get the current user ID from context",
          fn ctx, _params ->
            # ctx is a RunContext struct
            {:ok, %{user_id: ctx.deps.user_id, has_api_key: ctx.deps.api_key != nil}}
          end,
          parameters: %{},
          context_aware: true
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "What is my user ID?",
          model: "openai/gpt-3.5-turbo",
          tools: [tool],
          deps: deps
        )

      assert is_binary(response.content)
      assert response.content =~ ~r/123/
    end

    @tag :integration
    test "multiple context-aware tools access same dependencies" do
      deps = %{counter: 0, multiplier: 2}

      increment_tool =
        Tool.new(
          :increment,
          "Increment counter by 1",
          fn ctx, _params ->
            {:ok, ctx.deps.counter + 1}
          end,
          parameters: %{},
          context_aware: true
        )

      multiply_tool =
        Tool.new(
          :multiply,
          "Multiply a number by the multiplier",
          fn ctx, %{value: value} ->
            {:ok, value * ctx.deps.multiplier}
          end,
          parameters: %{
            value: [type: :number, required: true]
          },
          context_aware: true
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Increment the counter, then multiply the result by the multiplier",
          model: "openai/gpt-3.5-turbo",
          tools: [increment_tool, multiply_tool],
          deps: deps
        )

      assert is_binary(response.content)
      # Counter starts at 0, increment to 1, multiply by 2 = 2
      assert response.content =~ ~r/2/
    end

    @tag :integration
    test "context-aware tool can access RunContext metadata" do
      tool =
        Tool.new(
          :inspect_run_context,
          "Inspect the RunContext metadata",
          fn ctx, _params ->
            {:ok,
             %{
               model: ctx.model,
               has_deps: RunContext.has_deps?(ctx),
               message_count: RunContext.message_count(ctx)
             }}
          end,
          parameters: %{},
          context_aware: true
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Inspect the run context",
          model: "openai/gpt-3.5-turbo",
          tools: [tool],
          deps: %{app: "test"}
        )

      assert is_binary(response.content)
      # Should mention the model being used
      assert response.content =~ ~r/gpt-3.5-turbo|model|context/i
    end
  end

  describe "RunContext with database-like dependencies" do
    defmodule DatabaseDeps do
      defstruct [:conn, :user_id, :tenant_id]
    end

    defmodule FakeDB do
      def query(:test_conn, "SELECT name FROM users WHERE id = ?", [user_id]) do
        {:ok, "User_#{user_id}"}
      end

      def query(:test_conn, "SELECT COUNT(*) FROM orders WHERE user_id = ?", [user_id, _tenant]) do
        {:ok, user_id * 2}
      end
    end

    @tag :integration
    test "tools access injected database connection" do
      deps = %DatabaseDeps{
        conn: :test_conn,
        user_id: 5,
        tenant_id: 1
      }

      get_name_tool =
        Tool.new(
          :get_user_name,
          "Get user name from database",
          fn ctx, _params ->
            FakeDB.query(ctx.deps.conn, "SELECT name FROM users WHERE id = ?", [ctx.deps.user_id])
          end,
          parameters: %{},
          context_aware: true
        )

      count_orders_tool =
        Tool.new(
          :count_orders,
          "Count user orders",
          fn ctx, _params ->
            FakeDB.query(
              ctx.deps.conn,
              "SELECT COUNT(*) FROM orders WHERE user_id = ?",
              [ctx.deps.user_id, ctx.deps.tenant_id]
            )
          end,
          parameters: %{},
          context_aware: true
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Get my name and count my orders",
          model: "openai/gpt-3.5-turbo",
          tools: [get_name_tool, count_orders_tool],
          deps: deps
        )

      assert is_binary(response.content)
      assert response.content =~ ~r/User_5|name/i
      assert response.content =~ ~r/10|orders/i
    end
  end

  describe "RunContext with conversation history" do
    defmodule StateDeps do
      defstruct [:session_id, :state]
    end

    @tag :integration
    test "RunContext persists through multi-turn conversation" do
      # Simulated stateful storage
      {:ok, state_agent} = Agent.start_link(fn -> %{} end)

      save_tool =
        Tool.new(
          :save_value,
          "Save a value to state",
          fn ctx, %{key: key, value: value} ->
            Agent.update(state_agent, fn state ->
              Map.put(state, key, value)
            end)

            {:ok, "Saved #{key} = #{value} for session #{ctx.deps.session_id}"}
          end,
          parameters: %{
            key: [type: :string, required: true],
            value: [type: :string, required: true]
          },
          context_aware: true
        )

      retrieve_tool =
        Tool.new(
          :get_value,
          "Retrieve a saved value",
          fn _ctx, %{key: key} ->
            value = Agent.get(state_agent, fn state -> Map.get(state, key, "not found") end)
            {:ok, %{key: key, value: value}}
          end,
          parameters: %{
            key: [type: :string, required: true]
          },
          context_aware: true
        )

      deps = %StateDeps{session_id: "abc123", state: %{}}

      # First turn: save a value
      {:ok, response1} =
        Openrouter.Agent.run(
          "Save my favorite color as 'blue'",
          model: "openai/gpt-3.5-turbo",
          tools: [save_tool, retrieve_tool],
          deps: deps
        )

      assert response1.content =~ ~r/saved|blue/i

      # Second turn: retrieve the value
      messages = [
        %{role: :user, content: "Save my favorite color as 'blue'"},
        %{role: :assistant, content: response1.content},
        %{role: :user, content: "What's my favorite color?"}
      ]

      {:ok, response2} =
        Openrouter.Agent.run_with_history(
          messages,
          model: "openai/gpt-3.5-turbo",
          tools: [save_tool, retrieve_tool],
          deps: deps
        )

      assert response2.content =~ ~r/blue/i
    end
  end

  describe "RunContext with mixed tool types" do
    @tag :integration
    test "context-aware and regular tools work together" do
      deps = %{api_key: "secret123", user_id: 999}

      # Regular tool (no RunContext)
      add_tool =
        Tool.new(
          :add,
          "Add two numbers",
          fn %{a: a, b: b} ->
            {:ok, a + b}
          end,
          parameters: %{
            a: [type: :number, required: true],
            b: [type: :number, required: true]
          }
        )

      # Context-aware tool
      get_user_tool =
        Tool.new(
          :get_user_id,
          "Get user ID from context",
          fn ctx, _params ->
            {:ok, ctx.deps.user_id}
          end,
          parameters: %{},
          context_aware: true
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Add 5 and 3, then tell me my user ID",
          model: "openai/gpt-3.5-turbo",
          tools: [add_tool, get_user_tool],
          deps: deps
        )

      assert is_binary(response.content)
      assert response.content =~ ~r/8/
      assert response.content =~ ~r/999/
    end
  end

  describe "RunContext error handling" do
    @tag :integration
    test "handles context-aware tool without deps gracefully" do
      tool =
        Tool.new(
          :needs_deps,
          "A tool that needs dependencies",
          fn ctx, _params ->
            if ctx.deps do
              {:ok, "Has deps"}
            else
              {:ok, "No deps"}
            end
          end,
          parameters: %{},
          context_aware: true
        )

      # Run without deps
      {:ok, response} =
        Openrouter.Agent.run(
          "Use the tool",
          model: "openai/gpt-3.5-turbo",
          tools: [tool]
        )

      assert is_binary(response.content)
    end

    @tag :integration
    test "tool can check if deps exist" do
      tool =
        Tool.new(
          :check_deps,
          "Check if dependencies are available",
          fn ctx, _params ->
            has_deps = RunContext.has_deps?(ctx)
            {:ok, %{has_deps: has_deps}}
          end,
          parameters: %{},
          context_aware: true
        )

      # With deps
      {:ok, response1} =
        Openrouter.Agent.run(
          "Check if deps exist",
          model: "openai/gpt-3.5-turbo",
          tools: [tool],
          deps: %{user: "test"}
        )

      assert response1.content =~ ~r/true|available|exist/i

      # Without deps
      {:ok, response2} =
        Openrouter.Agent.run(
          "Check if deps exist",
          model: "openai/gpt-3.5-turbo",
          tools: [tool]
        )

      assert response2.content =~ ~r/false|not available|don't exist/i
    end
  end

  describe "RunContext with complex dependencies" do
    defmodule ComplexDeps do
      defstruct [:services, :config, :user_context]

      @type t :: %__MODULE__{
              services: map(),
              config: map(),
              user_context: map()
            }
    end

    @tag :integration
    test "handles nested dependency structures" do
      deps = %ComplexDeps{
        services: %{
          db: :fake_db,
          cache: :fake_cache,
          logger: :fake_logger
        },
        config: %{
          timeout: 5000,
          max_retries: 3
        },
        user_context: %{
          user_id: 777,
          role: :admin,
          permissions: [:read, :write, :delete]
        }
      }

      tool =
        Tool.new(
          :check_permission,
          "Check if user has permission",
          fn ctx, %{action: action} ->
            permissions = ctx.deps.user_context.permissions
            has_permission = String.to_atom(action) in permissions

            {:ok, %{action: action, allowed: has_permission, role: ctx.deps.user_context.role}}
          end,
          parameters: %{
            action: [type: :string, required: true, enum: ["read", "write", "delete"]]
          },
          context_aware: true
        )

      {:ok, response} =
        Openrouter.Agent.run(
          "Check if I can delete items",
          model: "openai/gpt-3.5-turbo",
          tools: [tool],
          deps: deps
        )

      assert is_binary(response.content)
      assert response.content =~ ~r/allowed|can|delete/i
    end
  end
end
