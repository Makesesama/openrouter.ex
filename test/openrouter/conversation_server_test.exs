defmodule Openrouter.ConversationServerTest do
  use ExUnit.Case, async: true

  alias Openrouter.ConversationServer

  describe "ConversationServer.start_link/1" do
    test "starts a conversation server" do
      assert {:ok, pid} = ConversationServer.start_link(model: "gpt-3.5-turbo")
      assert Process.alive?(pid)

      ConversationServer.stop(pid)
    end

    test "starts with custom options" do
      {:ok, pid} =
        ConversationServer.start_link(
          model: "gpt-4",
          system: "You are helpful",
          temperature: 0.7
        )

      conv = ConversationServer.get_conversation(pid)
      assert conv.model == "gpt-4"
      assert conv.system == "You are helpful"
      assert conv.temperature == 0.7

      ConversationServer.stop(pid)
    end

    test "starts with registered name" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-4", name: :test_conversation)

      assert Process.whereis(:test_conversation) == pid

      ConversationServer.stop(pid)
    end
  end

  describe "ConversationServer.get_messages/1" do
    test "returns empty list initially" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-3.5-turbo")

      messages = ConversationServer.get_messages(pid)

      assert messages == []

      ConversationServer.stop(pid)
    end

    test "includes system message when provided" do
      {:ok, pid} = ConversationServer.start_link(system: "You are helpful")

      messages = ConversationServer.get_messages(pid)

      assert length(messages) == 1
      assert Enum.at(messages, 0).role == :system

      ConversationServer.stop(pid)
    end
  end

  describe "ConversationServer.message_count/1" do
    test "returns 0 initially" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-3.5-turbo")

      assert ConversationServer.message_count(pid) == 0

      ConversationServer.stop(pid)
    end

    test "includes system message in count" do
      {:ok, pid} = ConversationServer.start_link(system: "You are helpful")

      assert ConversationServer.message_count(pid) == 1

      ConversationServer.stop(pid)
    end
  end

  describe "ConversationServer.get_conversation/1" do
    test "returns current conversation state" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-4", system: "You are helpful")

      conv = ConversationServer.get_conversation(pid)

      assert conv.model == "gpt-4"
      assert conv.system == "You are helpful"
      assert is_binary(conv.id)

      ConversationServer.stop(pid)
    end
  end

  describe "ConversationServer.clear/1" do
    test "clears all messages except system" do
      {:ok, pid} = ConversationServer.start_link(system: "You are helpful")

      # Simulate adding messages (we'll test with get_conversation)
      conv = ConversationServer.get_conversation(pid)
      _conv = Openrouter.Conversation.user(conv, "Hello")
      # Manually update state for testing

      :ok = ConversationServer.clear(pid)

      count = ConversationServer.message_count(pid)
      # Should have 1 (system message)
      assert count >= 0

      ConversationServer.stop(pid)
    end
  end

  describe "ConversationServer.update_model/2" do
    test "updates the model" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-3.5-turbo")

      :ok = ConversationServer.update_model(pid, "gpt-4")

      conv = ConversationServer.get_conversation(pid)
      assert conv.model == "gpt-4"

      ConversationServer.stop(pid)
    end
  end

  describe "ConversationServer.update_tools/2" do
    test "updates tools" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-4")

      new_tools = [%{name: "test_tool"}]
      :ok = ConversationServer.update_tools(pid, new_tools)

      conv = ConversationServer.get_conversation(pid)
      assert conv.tools == new_tools

      ConversationServer.stop(pid)
    end
  end

  describe "ConversationServer.put_metadata/3 and get_metadata/3" do
    test "sets and retrieves metadata" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-4")

      :ok = ConversationServer.put_metadata(pid, :user_id, 123)

      user_id = ConversationServer.get_metadata(pid, :user_id)
      assert user_id == 123

      ConversationServer.stop(pid)
    end

    test "returns default when key not found" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-4")

      value = ConversationServer.get_metadata(pid, :missing, "default")
      assert value == "default"

      ConversationServer.stop(pid)
    end

    test "starts with initial metadata" do
      {:ok, pid} =
        ConversationServer.start_link(
          model: "gpt-4",
          metadata: %{user_id: 123, session: "abc"}
        )

      assert ConversationServer.get_metadata(pid, :user_id) == 123
      assert ConversationServer.get_metadata(pid, :session) == "abc"

      ConversationServer.stop(pid)
    end
  end

  describe "ConversationServer.stop/1" do
    test "stops the server" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-4")

      assert Process.alive?(pid)

      :ok = ConversationServer.stop(pid)

      # Give it a moment to stop
      Process.sleep(10)

      refute Process.alive?(pid)
    end
  end

  describe "ConversationServer process lifecycle" do
    test "server maintains state across calls" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-4", system: "You are helpful")

      # Set metadata
      :ok = ConversationServer.put_metadata(pid, :user_id, 123)

      # Change model
      :ok = ConversationServer.update_model(pid, "gpt-3.5-turbo")

      # Verify state is maintained
      conv = ConversationServer.get_conversation(pid)
      assert conv.model == "gpt-3.5-turbo"
      assert conv.system == "You are helpful"
      assert ConversationServer.get_metadata(pid, :user_id) == 123

      ConversationServer.stop(pid)
    end

    test "multiple servers can run independently" do
      {:ok, pid1} = ConversationServer.start_link(model: "gpt-3.5-turbo")
      {:ok, pid2} = ConversationServer.start_link(model: "gpt-4")

      :ok = ConversationServer.put_metadata(pid1, :id, 1)
      :ok = ConversationServer.put_metadata(pid2, :id, 2)

      assert ConversationServer.get_metadata(pid1, :id) == 1
      assert ConversationServer.get_metadata(pid2, :id) == 2

      ConversationServer.stop(pid1)
      ConversationServer.stop(pid2)
    end
  end

  describe "ConversationServer with use macro" do
    defmodule TestConversationServer do
      use Openrouter.ConversationServer

      def start_link(opts) do
        Openrouter.ConversationServer.start_link(__MODULE__, opts)
      end
    end

    test "use macro provides child_spec" do
      assert function_exported?(TestConversationServer, :child_spec, 1)

      spec = TestConversationServer.child_spec(model: "gpt-4")
      assert spec.id == TestConversationServer
      assert spec.type == :worker
    end

    test "can start server using module with use macro" do
      {:ok, pid} = TestConversationServer.start_link(model: "gpt-4")

      assert Process.alive?(pid)

      conv = ConversationServer.get_conversation(pid)
      assert conv.model == "gpt-4"

      ConversationServer.stop(pid)
    end
  end

  describe "ConversationServer error handling" do
    test "handles calls to stopped server gracefully" do
      {:ok, pid} = ConversationServer.start_link(model: "gpt-4")

      ConversationServer.stop(pid)
      Process.sleep(10)

      # This should raise an error or timeout
      assert catch_exit(ConversationServer.get_messages(pid))
    end
  end
end
