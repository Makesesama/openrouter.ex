defmodule Openrouter.ConversationTest do
  use ExUnit.Case, async: true

  alias Openrouter.Conversation
  alias Openrouter.Types.Message

  describe "Conversation.start/1" do
    test "creates a new conversation with defaults" do
      {:ok, conv} = Conversation.start()

      assert conv.id
      assert conv.client
      assert conv.messages == []
      assert conv.model == nil
      assert conv.system == nil
      assert conv.tools == []
      assert conv.metadata == %{}
    end

    test "creates conversation with custom options" do
      {:ok, conv} =
        Conversation.start(
          model: "gpt-4",
          system: "You are helpful",
          temperature: 0.7,
          max_tokens: 100
        )

      assert conv.model == "gpt-4"
      assert conv.system == "You are helpful"
      assert conv.temperature == 0.7
      assert conv.max_tokens == 100
    end

    test "adds system message when system option provided" do
      {:ok, conv} = Conversation.start(system: "You are helpful")

      assert length(conv.messages) == 1
      assert Enum.at(conv.messages, 0).role == :system
      assert Enum.at(conv.messages, 0).content == "You are helpful"
    end

    test "creates conversation with custom ID" do
      custom_id = "my-conversation-123"
      {:ok, conv} = Conversation.start(id: custom_id)

      assert conv.id == custom_id
    end

    test "creates conversation with tools" do
      tools = [%{name: "test_tool"}]
      {:ok, conv} = Conversation.start(tools: tools)

      assert conv.tools == tools
    end

    test "creates conversation with metadata" do
      metadata = %{user_id: 123, session: "abc"}
      {:ok, conv} = Conversation.start(metadata: metadata)

      assert conv.metadata == metadata
    end
  end

  describe "Conversation.user/2" do
    test "adds user message to conversation" do
      {:ok, conv} = Conversation.start()

      conv = Conversation.user(conv, "Hello")

      assert length(conv.messages) == 1
      assert Enum.at(conv.messages, 0).role == :user
      assert Enum.at(conv.messages, 0).content == "Hello"
    end

    test "adds multiple user messages" do
      {:ok, conv} = Conversation.start()

      conv =
        conv
        |> Conversation.user("First")
        |> Conversation.user("Second")

      assert length(conv.messages) == 2
      assert Enum.at(conv.messages, 0).content == "First"
      assert Enum.at(conv.messages, 1).content == "Second"
    end

    test "preserves system message when adding user message" do
      {:ok, conv} = Conversation.start(system: "You are helpful")

      conv = Conversation.user(conv, "Hello")

      assert length(conv.messages) == 2
      assert Enum.at(conv.messages, 0).role == :system
      assert Enum.at(conv.messages, 1).role == :user
    end
  end

  describe "Conversation.assistant/2" do
    test "adds assistant message to conversation" do
      {:ok, conv} = Conversation.start()

      conv = Conversation.assistant(conv, "Hi there!")

      assert length(conv.messages) == 1
      assert Enum.at(conv.messages, 0).role == :assistant
      assert Enum.at(conv.messages, 0).content == "Hi there!"
    end

    test "can alternate user and assistant messages" do
      {:ok, conv} = Conversation.start()

      conv =
        conv
        |> Conversation.user("Hello")
        |> Conversation.assistant("Hi!")
        |> Conversation.user("How are you?")

      assert length(conv.messages) == 3
      assert Enum.at(conv.messages, 0).role == :user
      assert Enum.at(conv.messages, 1).role == :assistant
      assert Enum.at(conv.messages, 2).role == :user
    end
  end

  describe "Conversation.message/2" do
    test "adds custom message to conversation" do
      {:ok, conv} = Conversation.start()

      message = %{role: :user, content: "Custom message"}
      conv = Conversation.message(conv, message)

      assert length(conv.messages) == 1
      assert Enum.at(conv.messages, 0) == message
    end

    test "adds Message struct" do
      {:ok, conv} = Conversation.start()

      message = Message.new(:user, "Test")
      conv = Conversation.message(conv, message)

      assert length(conv.messages) == 1
      assert Enum.at(conv.messages, 0).content == "Test"
    end
  end

  describe "Conversation.messages/1" do
    test "returns all messages" do
      {:ok, conv} = Conversation.start()

      conv =
        conv
        |> Conversation.user("First")
        |> Conversation.assistant("Second")

      messages = Conversation.messages(conv)

      assert length(messages) == 2
    end

    test "returns empty list when no messages" do
      {:ok, conv} = Conversation.start()

      assert Conversation.messages(conv) == []
    end
  end

  describe "Conversation.message_count/1" do
    test "returns correct count" do
      {:ok, conv} = Conversation.start()

      assert Conversation.message_count(conv) == 0

      conv = Conversation.user(conv, "Hello")
      assert Conversation.message_count(conv) == 1

      conv = Conversation.assistant(conv, "Hi")
      assert Conversation.message_count(conv) == 2
    end

    test "includes system message in count" do
      {:ok, conv} = Conversation.start(system: "You are helpful")

      assert Conversation.message_count(conv) == 1
    end
  end

  describe "Conversation.last_messages/2" do
    test "returns last N messages" do
      {:ok, conv} = Conversation.start()

      conv =
        conv
        |> Conversation.user("First")
        |> Conversation.assistant("Second")
        |> Conversation.user("Third")
        |> Conversation.assistant("Fourth")

      last_2 = Conversation.last_messages(conv, 2)

      assert length(last_2) == 2
      assert Enum.at(last_2, 0).content == "Third"
      assert Enum.at(last_2, 1).content == "Fourth"
    end

    test "returns all messages when N is larger" do
      {:ok, conv} = Conversation.start()

      conv =
        conv
        |> Conversation.user("First")
        |> Conversation.user("Second")

      last = Conversation.last_messages(conv, 10)

      assert length(last) == 2
    end
  end

  describe "Conversation.clear/1" do
    test "removes all messages" do
      {:ok, conv} = Conversation.start()

      conv =
        conv
        |> Conversation.user("First")
        |> Conversation.assistant("Second")
        |> Conversation.user("Third")

      cleared = Conversation.clear(conv)

      assert Conversation.message_count(cleared) == 0
    end

    test "preserves system message when clearing" do
      {:ok, conv} = Conversation.start(system: "You are helpful")

      conv =
        conv
        |> Conversation.user("Hello")
        |> Conversation.assistant("Hi")

      cleared = Conversation.clear(conv)

      assert Conversation.message_count(cleared) == 1
      assert Enum.at(cleared.messages, 0).role == :system
    end

    test "preserves conversation configuration" do
      {:ok, conv} =
        Conversation.start(
          model: "gpt-4",
          temperature: 0.7,
          metadata: %{user_id: 123}
        )

      conv = Conversation.user(conv, "Hello")
      cleared = Conversation.clear(conv)

      assert cleared.model == "gpt-4"
      assert cleared.temperature == 0.7
      assert cleared.metadata == %{user_id: 123}
    end
  end

  describe "Conversation.put_metadata/3 and get_metadata/3" do
    test "sets and retrieves metadata" do
      {:ok, conv} = Conversation.start()

      conv = Conversation.put_metadata(conv, :user_id, 123)
      assert Conversation.get_metadata(conv, :user_id) == 123
    end

    test "returns default when key not found" do
      {:ok, conv} = Conversation.start()

      assert Conversation.get_metadata(conv, :missing, "default") == "default"
    end

    test "returns nil when key not found and no default" do
      {:ok, conv} = Conversation.start()

      assert Conversation.get_metadata(conv, :missing) == nil
    end

    test "updates existing metadata" do
      {:ok, conv} = Conversation.start(metadata: %{user_id: 123})

      conv = Conversation.put_metadata(conv, :user_id, 456)
      assert Conversation.get_metadata(conv, :user_id) == 456
    end

    test "preserves other metadata when updating" do
      {:ok, conv} = Conversation.start()

      conv =
        conv
        |> Conversation.put_metadata(:user_id, 123)
        |> Conversation.put_metadata(:session, "abc")

      assert Conversation.get_metadata(conv, :user_id) == 123
      assert Conversation.get_metadata(conv, :session) == "abc"
    end
  end

  describe "Conversation.update_model/2" do
    test "updates the model" do
      {:ok, conv} = Conversation.start(model: "gpt-3.5-turbo")

      conv = Conversation.update_model(conv, "gpt-4")

      assert conv.model == "gpt-4"
    end

    test "sets model when initially nil" do
      {:ok, conv} = Conversation.start()

      conv = Conversation.update_model(conv, "gpt-4")

      assert conv.model == "gpt-4"
    end
  end

  describe "Conversation.update_tools/2" do
    test "updates tools" do
      {:ok, conv} = Conversation.start(tools: [%{name: "old"}])

      new_tools = [%{name: "new1"}, %{name: "new2"}]
      conv = Conversation.update_tools(conv, new_tools)

      assert conv.tools == new_tools
    end

    test "replaces existing tools" do
      {:ok, conv} = Conversation.start(tools: [%{name: "tool1"}])

      conv = Conversation.update_tools(conv, [])

      assert conv.tools == []
    end
  end

  describe "Conversation persistence (ETS)" do
    test "saves and loads conversation" do
      {:ok, conv} = Conversation.start(model: "gpt-4", system: "You are helpful")

      conv = Conversation.user(conv, "Hello")

      # Save
      :ok = Conversation.save(conv, to: :ets)

      # Load
      {:ok, loaded} = Conversation.load(conv.id, from: :ets)

      assert loaded.id == conv.id
      assert loaded.model == conv.model
      assert loaded.system == conv.system
      assert Conversation.message_count(loaded) == Conversation.message_count(conv)

      # Clean up
      Conversation.delete(conv.id, from: :ets)
    end

    test "returns error when loading non-existent conversation" do
      result = Conversation.load("non-existent-id", from: :ets)

      assert {:error, :not_found} = result
    end

    test "deletes conversation" do
      {:ok, conv} = Conversation.start()
      :ok = Conversation.save(conv, to: :ets)

      :ok = Conversation.delete(conv.id, from: :ets)

      assert {:error, :not_found} = Conversation.load(conv.id, from: :ets)
    end
  end

  describe "Conversation immutability" do
    test "operations return new conversations" do
      {:ok, original} = Conversation.start()

      updated = Conversation.user(original, "Hello")

      # Original is unchanged
      assert Conversation.message_count(original) == 0
      # Updated has new message
      assert Conversation.message_count(updated) == 1
    end

    test "multiple branches from same conversation" do
      {:ok, conv} = Conversation.start()

      branch1 = Conversation.user(conv, "Branch 1")
      branch2 = Conversation.user(conv, "Branch 2")

      # Branches are independent
      assert Enum.at(branch1.messages, 0).content == "Branch 1"
      assert Enum.at(branch2.messages, 0).content == "Branch 2"
      # Original is unchanged
      assert Conversation.message_count(conv) == 0
    end
  end
end
