#!/usr/bin/env elixir
#
# Conversation Management Examples
#
# This file demonstrates both stateless (Conversation) and stateful
# (ConversationServer) conversation management.
#
# Run with: mix run examples/conversation.exs

Mix.install([{:openrouter, path: "."}])

require Logger

IO.puts("\n=== Conversation Management Examples ===\n")

# ============================================================================
# Example 1: Basic Stateless Conversation
# ============================================================================

IO.puts("1. Basic Stateless Conversation")
IO.puts("   Using Conversation module for multi-turn interactions\n")

{:ok, conv} =
  Openrouter.Conversation.start(
    model: "openai/gpt-3.5-turbo",
    system: "You are a helpful assistant. Keep responses concise."
  )

# First turn
conv = Openrouter.Conversation.user(conv, "What is the capital of France?")
{:ok, conv, response1} = Openrouter.Conversation.complete(conv)
IO.puts("Turn 1: #{response1.content}")

# Second turn
conv = Openrouter.Conversation.user(conv, "What's its population?")
{:ok, conv, response2} = Openrouter.Conversation.complete(conv)
IO.puts("Turn 2: #{response2.content}")

# Show message count
IO.puts("Total messages: #{Openrouter.Conversation.message_count(conv)}\n")

# ============================================================================
# Example 2: Conversation with Tools (Stateless)
# ============================================================================

IO.puts("2. Conversation with Tools")
IO.puts("   Using Agent automatic tool execution in conversations\n")

calculator_tool =
  Openrouter.Tool.new(
    :calculate,
    "Perform arithmetic operations",
    fn %{operation: op, a: a, b: b} ->
      result =
        case op do
          "add" -> a + b
          "multiply" -> a * b
          "subtract" -> a - b
          "divide" when b != 0 -> a / b
        end

      {:ok, result}
    end,
    parameters: %{
      operation: [type: :string, required: true, enum: ["add", "multiply", "subtract", "divide"]],
      a: [type: :number, required: true],
      b: [type: :number, required: true]
    }
  )

{:ok, conv} =
  Openrouter.Conversation.start(
    model: "openai/gpt-3.5-turbo",
    tools: [calculator_tool],
    system: "You are a helpful math assistant."
  )

conv = Openrouter.Conversation.user(conv, "What is 25 multiplied by 4?")
{:ok, conv, response} = Openrouter.Conversation.complete_with_agent(conv)
IO.puts("Result: #{response.content}")

# Continue conversation
conv = Openrouter.Conversation.user(conv, "Now add 10 to that result")
{:ok, conv, response} = Openrouter.Conversation.complete_with_agent(conv)
IO.puts("Result: #{response.content}\n")

# ============================================================================
# Example 3: Conversation Persistence
# ============================================================================

IO.puts("3. Conversation Persistence")
IO.puts("   Saving and loading conversations from ETS\n")

{:ok, conv} =
  Openrouter.Conversation.start(
    model: "openai/gpt-3.5-turbo",
    system: "You are a helpful assistant"
  )

conv = Openrouter.Conversation.user(conv, "Remember that my name is Alice")
{:ok, conv, response} = Openrouter.Conversation.complete(conv)
IO.puts("Response: #{response.content}")

# Save conversation
conversation_id = conv.id
:ok = Openrouter.Conversation.save(conv, to: :ets)
IO.puts("Saved conversation with ID: #{conversation_id}")

# Load conversation later
{:ok, loaded_conv} = Openrouter.Conversation.load(conversation_id, from: :ets)
IO.puts("Loaded conversation, messages: #{Openrouter.Conversation.message_count(loaded_conv)}")

# Continue from loaded conversation
loaded_conv = Openrouter.Conversation.user(loaded_conv, "What's my name?")
{:ok, loaded_conv, response} = Openrouter.Conversation.complete(loaded_conv)
IO.puts("Response: #{response.content}\n")

# Clean up
Openrouter.Conversation.delete(conversation_id, from: :ets)

# ============================================================================
# Example 4: Stateful Conversation with ConversationServer
# ============================================================================

IO.puts("4. Stateful Conversation with ConversationServer")
IO.puts("   Using GenServer for automatic state management\n")

{:ok, pid} =
  Openrouter.ConversationServer.start_link(
    model: "openai/gpt-3.5-turbo",
    system: "You are a helpful assistant. Be concise."
  )

# Send first message
{:ok, response1} = Openrouter.ConversationServer.send_message(pid, "Hi, my favorite color is blue")
IO.puts("Turn 1: #{response1.content}")

# Send second message - context is automatically maintained
{:ok, response2} = Openrouter.ConversationServer.send_message(pid, "What's my favorite color?")
IO.puts("Turn 2: #{response2.content}")

# Check message count
count = Openrouter.ConversationServer.message_count(pid)
IO.puts("Messages in conversation: #{count}")

# Get all messages
messages = Openrouter.ConversationServer.get_messages(pid)
IO.puts("\nConversation history:")

Enum.each(messages, fn msg ->
  role = Map.get(msg, :role, "unknown")
  content = Map.get(msg, :content, "")
  IO.puts("  #{role}: #{String.slice(content, 0..50)}...")
end)

# Stop the server
:ok = Openrouter.ConversationServer.stop(pid)
IO.puts("")

# ============================================================================
# Example 5: ConversationServer with Tools
# ============================================================================

IO.puts("5. ConversationServer with Automatic Tool Execution")
IO.puts("   Tools are automatically executed by the server\n")

weather_tool =
  Openrouter.Tool.new(
    :get_weather,
    "Get weather for a location",
    fn %{location: location} ->
      # Simulated weather data
      conditions = ["sunny", "cloudy", "rainy"]
      temp = Enum.random(60..85)
      condition = Enum.random(conditions)

      {:ok, "The weather in #{location} is #{condition}, #{temp}°F"}
    end,
    parameters: %{
      location: [type: :string, required: true]
    }
  )

{:ok, pid} =
  Openrouter.ConversationServer.start_link(
    model: "openai/gpt-3.5-turbo",
    tools: [weather_tool],
    use_agent: true # Enable automatic tool execution
  )

{:ok, response} =
  Openrouter.ConversationServer.send_message(pid, "What's the weather in Seattle?")

IO.puts("Response: #{response.content}")

# Continue conversation
{:ok, response} =
  Openrouter.ConversationServer.send_message(pid, "What about in Portland?")

IO.puts("Response: #{response.content}\n")

:ok = Openrouter.ConversationServer.stop(pid)

# ============================================================================
# Example 6: ConversationServer with Metadata
# ============================================================================

IO.puts("6. ConversationServer with Custom Metadata")
IO.puts("   Storing custom data alongside conversations\n")

{:ok, pid} =
  Openrouter.ConversationServer.start_link(
    model: "openai/gpt-3.5-turbo",
    metadata: %{user_id: 123, session_type: "support"}
  )

# Set additional metadata
:ok = Openrouter.ConversationServer.put_metadata(pid, :support_tier, "premium")
:ok = Openrouter.ConversationServer.put_metadata(pid, :agent_name, "Alice")

# Retrieve metadata
user_id = Openrouter.ConversationServer.get_metadata(pid, :user_id)
tier = Openrouter.ConversationServer.get_metadata(pid, :support_tier)
agent = Openrouter.ConversationServer.get_metadata(pid, :agent_name)

IO.puts("User ID: #{user_id}")
IO.puts("Support Tier: #{tier}")
IO.puts("Agent: #{agent}")

{:ok, _response} =
  Openrouter.ConversationServer.send_message(pid, "I need help with my account")

:ok = Openrouter.ConversationServer.stop(pid)
IO.puts("")

# ============================================================================
# Example 7: Dynamic Model Switching
# ============================================================================

IO.puts("7. Dynamic Model Switching")
IO.puts("   Changing models mid-conversation\n")

{:ok, pid} =
  Openrouter.ConversationServer.start_link(
    model: "openai/gpt-3.5-turbo",
    system: "You are a helpful assistant"
  )

{:ok, response1} = Openrouter.ConversationServer.send_message(pid, "What model are you?")
IO.puts("With GPT-3.5: #{response1.content}")

# Switch to GPT-4
:ok = Openrouter.ConversationServer.update_model(pid, "openai/gpt-4")

{:ok, response2} = Openrouter.ConversationServer.send_message(pid, "What model are you now?")
IO.puts("With GPT-4: #{response2.content}\n")

:ok = Openrouter.ConversationServer.stop(pid)

# ============================================================================
# Example 8: Clearing Conversation History
# ============================================================================

IO.puts("8. Clearing Conversation History")
IO.puts("   Resetting conversations while keeping configuration\n")

{:ok, pid} =
  Openrouter.ConversationServer.start_link(
    model: "openai/gpt-3.5-turbo",
    system: "You are a helpful assistant"
  )

{:ok, _} = Openrouter.ConversationServer.send_message(pid, "My name is Bob")
{:ok, _} = Openrouter.ConversationServer.send_message(pid, "I live in Seattle")

count_before = Openrouter.ConversationServer.message_count(pid)
IO.puts("Messages before clear: #{count_before}")

# Clear the conversation
:ok = Openrouter.ConversationServer.clear(pid)

count_after = Openrouter.ConversationServer.message_count(pid)
IO.puts("Messages after clear: #{count_after}")

# The model and system message are preserved
{:ok, response} = Openrouter.ConversationServer.send_message(pid, "What's my name?")
IO.puts("After clear: #{response.content}\n")

:ok = Openrouter.ConversationServer.stop(pid)

# ============================================================================
# Example 9: Comparing Stateless vs Stateful
# ============================================================================

IO.puts("9. Stateless vs Stateful Comparison\n")

IO.puts("Stateless (Conversation):")
IO.puts("  - Functional, immutable API")
IO.puts("  - Manual state management")
IO.puts("  - Easy to test and reason about")
IO.puts("  - Good for request/response patterns")
IO.puts("  - Can be saved/loaded easily")

IO.puts("\nStateful (ConversationServer):")
IO.puts("  - GenServer-based")
IO.puts("  - Automatic state management")
IO.puts("  - Good for long-running conversations")
IO.puts("  - Phoenix integration (LiveView, Channels)")
IO.puts("  - Can be supervised")
IO.puts("  - Supports streaming")

IO.puts("")

# ============================================================================
# Example 10: Conversation Helper Functions
# ============================================================================

IO.puts("10. Conversation Helper Functions")
IO.puts("    Inspecting and manipulating conversations\n")

{:ok, conv} =
  Openrouter.Conversation.start(
    model: "gpt-3.5-turbo",
    system: "You are a helpful assistant"
  )

conv = Openrouter.Conversation.user(conv, "First message")
{:ok, conv, _} = Openrouter.Conversation.complete(conv)

conv = Openrouter.Conversation.user(conv, "Second message")
{:ok, conv, _} = Openrouter.Conversation.complete(conv)

conv = Openrouter.Conversation.user(conv, "Third message")

# Get last N messages
last_3 = Openrouter.Conversation.last_messages(conv, 3)
IO.puts("Last 3 messages: #{length(last_3)} messages")

# Get all messages
all = Openrouter.Conversation.messages(conv)
IO.puts("Total messages: #{length(all)}")

# Message count
count = Openrouter.Conversation.message_count(conv)
IO.puts("Message count: #{count}")

IO.puts("")

IO.puts("=== All Conversation Examples Complete ===\n")
