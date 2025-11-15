defmodule Openrouter.Integration.ConversationTest do
  use Reqord.Case

  @moduletag :integration
  @moduletag :conversation

  alias Openrouter.{Conversation, ConversationServer, Tool}

  describe "Conversation (stateless)" do
    @tag :integration
    test "basic multi-turn conversation" do
      {:ok, conv} =
        Conversation.start(
          model: "openai/gpt-3.5-turbo",
          system: "You are a helpful assistant. Keep responses very concise (one sentence max)."
        )

      # First turn
      conv = Conversation.user(conv, "What is 2+2?")
      {:ok, conv, response1} = Conversation.complete(conv)

      assert is_binary(response1.content)
      assert response1.content =~ ~r/4|four/i

      # Second turn
      conv = Conversation.user(conv, "What's that number times 2?")
      {:ok, conv, response2} = Conversation.complete(conv)

      assert is_binary(response2.content)
      assert response2.content =~ ~r/8|eight/i

      # Verify message history
      # system + 2 user + 2 assistant
      assert Conversation.message_count(conv) >= 5
    end

    @tag :integration
    test "conversation with tools using agent" do
      calculator_tool =
        Tool.new(
          :add,
          "Add two numbers",
          fn %{a: a, b: b} -> {:ok, a + b} end,
          parameters: %{
            a: [type: :number, required: true],
            b: [type: :number, required: true]
          }
        )

      {:ok, conv} =
        Conversation.start(
          model: "openai/gpt-3.5-turbo",
          tools: [calculator_tool]
        )

      conv = Conversation.user(conv, "What is 15 plus 27?")
      {:ok, conv, response} = Conversation.complete_with_agent(conv)

      assert is_binary(response.content)
      assert response.content =~ ~r/42/
    end

    @tag :integration
    test "conversation persistence" do
      {:ok, conv} =
        Conversation.start(
          model: "openai/gpt-3.5-turbo",
          system: "You are helpful. Keep responses to one sentence."
        )

      conv = Conversation.user(conv, "Remember that my favorite color is blue")
      {:ok, conv, response1} = Conversation.complete(conv)

      assert is_binary(response1.content)

      # Save conversation
      conversation_id = conv.id
      :ok = Conversation.save(conv, to: :ets)

      # Load conversation
      {:ok, loaded_conv} = Conversation.load(conversation_id, from: :ets)

      # Verify loaded conversation has same history
      assert Conversation.message_count(loaded_conv) == Conversation.message_count(conv)

      # Continue from loaded conversation
      loaded_conv = Conversation.user(loaded_conv, "What's my favorite color?")
      {:ok, _loaded_conv, response2} = Conversation.complete(loaded_conv)

      assert response2.content =~ ~r/blue/i

      # Clean up
      Conversation.delete(conversation_id, from: :ets)
    end

    @tag :integration
    test "conversation with model override" do
      {:ok, conv} =
        Conversation.start(
          model: "openai/gpt-3.5-turbo",
          system: "Answer in one word."
        )

      conv = Conversation.user(conv, "What is 1+1?")

      # Override model for this completion
      {:ok, _conv, response} = Conversation.complete(conv, model: "openai/gpt-4")

      assert is_binary(response.content)
    end

    @tag :integration
    test "conversation clear preserves system message" do
      {:ok, conv} =
        Conversation.start(
          model: "openai/gpt-3.5-turbo",
          system: "You are helpful. Keep responses to one sentence."
        )

      conv = Conversation.user(conv, "Hello")
      {:ok, conv, _response} = Conversation.complete(conv)

      # Should have multiple messages
      count_before = Conversation.message_count(conv)
      assert count_before > 1

      # Clear conversation
      conv = Conversation.clear(conv)

      # Should only have system message
      assert Conversation.message_count(conv) == 1
      assert Enum.at(conv.messages, 0).role == :system

      # Can continue from cleared state
      conv = Conversation.user(conv, "What is 2+2?")
      {:ok, _conv, response} = Conversation.complete(conv)

      assert is_binary(response.content)
    end

    @tag :integration
    test "conversation with metadata" do
      {:ok, conv} =
        Conversation.start(
          model: "openai/gpt-3.5-turbo",
          metadata: %{user_id: 123, session: "abc"}
        )

      conv = Conversation.put_metadata(conv, :request_count, 1)

      conv = Conversation.user(conv, "Hello")
      {:ok, conv, _response} = Conversation.complete(conv)

      # Metadata should be preserved
      assert Conversation.get_metadata(conv, :user_id) == 123
      assert Conversation.get_metadata(conv, :session) == "abc"
      assert Conversation.get_metadata(conv, :request_count) == 1
    end
  end

  describe "ConversationServer (stateful)" do
    @tag :integration
    test "basic stateful conversation" do
      {:ok, pid} =
        ConversationServer.start_link(
          model: "openai/gpt-3.5-turbo",
          system: "You are helpful. Keep responses to one sentence."
        )

      # First message
      {:ok, response1} = ConversationServer.send_message(pid, "My name is Alice")

      assert is_binary(response1.content)

      # Second message - should remember context
      {:ok, response2} = ConversationServer.send_message(pid, "What's my name?")

      assert response2.content =~ ~r/Alice/i

      # Verify message count
      count = ConversationServer.message_count(pid)
      # system + 2 user + 2 assistant (minimum)
      assert count >= 4

      ConversationServer.stop(pid)
    end

    @tag :integration
    test "conversation server with tools" do
      add_tool =
        Tool.new(
          :add,
          "Add two numbers",
          fn %{a: a, b: b} -> {:ok, a + b} end,
          parameters: %{
            a: [type: :number, required: true],
            b: [type: :number, required: true]
          }
        )

      {:ok, pid} =
        ConversationServer.start_link(
          model: "openai/gpt-3.5-turbo",
          tools: [add_tool],
          use_agent: true
        )

      {:ok, response} = ConversationServer.send_message(pid, "What is 25 + 17?")

      assert is_binary(response.content)
      assert response.content =~ ~r/42/

      ConversationServer.stop(pid)
    end

    @tag :integration
    test "conversation server clear maintains config" do
      {:ok, pid} =
        ConversationServer.start_link(
          model: "openai/gpt-3.5-turbo",
          system: "You are helpful. Be concise."
        )

      {:ok, _} = ConversationServer.send_message(pid, "My favorite number is 7")

      count_before = ConversationServer.message_count(pid)
      assert count_before > 1

      # Clear messages
      :ok = ConversationServer.clear(pid)

      count_after = ConversationServer.message_count(pid)
      assert count_after <= count_before

      # System message should still be there
      conv = ConversationServer.get_conversation(pid)
      assert conv.system == "You are helpful. Be concise."

      # Can continue conversation
      {:ok, response} = ConversationServer.send_message(pid, "What is 2+2?")
      assert is_binary(response.content)

      ConversationServer.stop(pid)
    end

    @tag :integration
    test "conversation server model update" do
      {:ok, pid} =
        ConversationServer.start_link(
          model: "openai/gpt-3.5-turbo",
          system: "Answer in one word."
        )

      # Send a message with original model
      {:ok, _response1} = ConversationServer.send_message(pid, "What is 1+1?")

      # Update model
      :ok = ConversationServer.update_model(pid, "openai/gpt-4")

      # Send another message with new model
      {:ok, response2} = ConversationServer.send_message(pid, "What is 2+2?")

      assert is_binary(response2.content)

      # Verify model was updated
      conv = ConversationServer.get_conversation(pid)
      assert conv.model == "openai/gpt-4"

      ConversationServer.stop(pid)
    end

    @tag :integration
    test "conversation server metadata" do
      {:ok, pid} =
        ConversationServer.start_link(
          model: "openai/gpt-3.5-turbo",
          metadata: %{user_id: 123}
        )

      # Set additional metadata
      :ok = ConversationServer.put_metadata(pid, :session_id, "abc123")

      # Send a message
      {:ok, _response} = ConversationServer.send_message(pid, "Hello")

      # Verify metadata persists
      assert ConversationServer.get_metadata(pid, :user_id) == 123
      assert ConversationServer.get_metadata(pid, :session_id) == "abc123"

      ConversationServer.stop(pid)
    end

    @tag :integration
    test "multiple conversation servers independently" do
      {:ok, pid1} =
        ConversationServer.start_link(
          model: "openai/gpt-3.5-turbo",
          system: "Answer in one sentence."
        )

      {:ok, pid2} =
        ConversationServer.start_link(
          model: "openai/gpt-3.5-turbo",
          system: "Answer in one sentence."
        )

      # Send different messages to each
      {:ok, _} = ConversationServer.send_message(pid1, "My name is Alice")
      {:ok, _} = ConversationServer.send_message(pid2, "My name is Bob")

      # Verify they maintain separate state
      {:ok, response1} = ConversationServer.send_message(pid1, "What's my name?")
      {:ok, response2} = ConversationServer.send_message(pid2, "What's my name?")

      assert response1.content =~ ~r/Alice/i
      assert response2.content =~ ~r/Bob/i

      ConversationServer.stop(pid1)
      ConversationServer.stop(pid2)
    end

    @tag :integration
    test "conversation server with tools and multi-turn" do
      calculator_tool =
        Tool.new(
          :calculate,
          "Perform arithmetic",
          fn %{op: op, a: a, b: b} ->
            result =
              case op do
                "add" -> a + b
                "multiply" -> a * b
              end

            {:ok, result}
          end,
          parameters: %{
            op: [type: :string, required: true, enum: ["add", "multiply"]],
            a: [type: :number, required: true],
            b: [type: :number, required: true]
          }
        )

      {:ok, pid} =
        ConversationServer.start_link(
          model: "openai/gpt-3.5-turbo",
          tools: [calculator_tool],
          use_agent: true
        )

      # First calculation
      {:ok, response1} = ConversationServer.send_message(pid, "What is 5 times 4?")
      assert response1.content =~ ~r/20/

      # Second calculation - should maintain context
      {:ok, response2} = ConversationServer.send_message(pid, "Now add 10 to that")
      assert response2.content =~ ~r/30/

      ConversationServer.stop(pid)
    end
  end

  describe "Conversation vs ConversationServer comparison" do
    @tag :integration
    test "stateless and stateful produce same results" do
      prompt1 = "What is 2+2?"
      prompt2 = "What is that times 3?"

      # Stateless approach
      {:ok, conv} =
        Conversation.start(
          model: "openai/gpt-3.5-turbo",
          system: "You are a math tutor. Answer in one sentence."
        )

      conv = Conversation.user(conv, prompt1)
      {:ok, conv, response1_stateless} = Conversation.complete(conv)

      conv = Conversation.user(conv, prompt2)
      {:ok, _conv, response2_stateless} = Conversation.complete(conv)

      # Stateful approach
      {:ok, pid} =
        ConversationServer.start_link(
          model: "openai/gpt-3.5-turbo",
          system: "You are a math tutor. Answer in one sentence."
        )

      {:ok, response1_stateful} = ConversationServer.send_message(pid, prompt1)
      {:ok, response2_stateful} = ConversationServer.send_message(pid, prompt2)

      # Both should mention 4 in first response
      assert response1_stateless.content =~ ~r/4|four/i
      assert response1_stateful.content =~ ~r/4|four/i

      # Both should mention 12 in second response
      assert response2_stateless.content =~ ~r/12|twelve/i
      assert response2_stateful.content =~ ~r/12|twelve/i

      ConversationServer.stop(pid)
    end
  end
end
