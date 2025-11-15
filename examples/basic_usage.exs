# Basic Usage Examples for Openrouter.ex
#
# To run these examples, first set your API key:
#   export OPENROUTER_API_KEY="or-..."
#
# Then run this file:
#   mix run examples/basic_usage.exs

# Start the application to load configuration
Application.ensure_all_started(:openrouter)

# Example 1: Simple chat
IO.puts("\n=== Example 1: Simple Chat ===")

case Openrouter.chat("What is the capital of France?", model: "anthropic/claude-sonnet-4.5") do
  {:ok, response} ->
    IO.puts("Response: #{response.content}")
    IO.puts("Model: #{response.model}")
    IO.puts("Tokens: #{response.usage.total_tokens}")

  {:error, error} ->
    IO.puts("Error: #{error.message}")
end

# Example 2: Chat with conversation history
IO.puts("\n=== Example 2: Conversation History ===")

messages = [
  %{role: :system, content: "You are a helpful math tutor"},
  %{role: :user, content: "What's 15 + 27?"},
  %{role: :assistant, content: "15 + 27 = 42"},
  %{role: :user, content: "Now multiply that by 2"}
]

case Openrouter.chat(messages, model: "openai/gpt-4") do
  {:ok, response} ->
    IO.puts("Response: #{response.content}")

  {:error, error} ->
    IO.puts("Error: #{error.message}")
end

# Example 3: Using a client
IO.puts("\n=== Example 3: Using a Client ===")

client =
  Openrouter.new(
    model: "anthropic/claude-sonnet-4.5",
    temperature: 0.7
  )

{:ok, response1} = Openrouter.chat(client, "Tell me a fun fact about space")
IO.puts("Fact 1: #{response1.content}")

{:ok, response2} = Openrouter.chat(client, "Tell me another one")
IO.puts("Fact 2: #{response2.content}")

# Example 4: Streaming
IO.puts("\n=== Example 4: Streaming Response ===")

case Openrouter.chat_stream(
       "Write a short haiku about coding",
       model: "openai/gpt-4",
       temperature: 0.8
     ) do
  {:ok, stream} ->
    IO.puts("Streaming response:")

    stream
    |> Stream.each(fn
      %{type: :content, content: text} ->
        IO.write(text)

      %{type: :done, finish_reason: reason} ->
        IO.puts("\n[Done: #{reason}]")

      _ ->
        :ok
    end)
    |> Stream.run()

  {:error, error} ->
    IO.puts("Error: #{error.message}")
end

# Example 5: Embeddings
IO.puts("\n=== Example 5: Embeddings ===")

case Openrouter.embed("The quick brown fox jumps over the lazy dog",
       model: "text-embedding-3-small"
     ) do
  {:ok, [embedding]} ->
    IO.puts("Embedding dimensions: #{length(embedding)}")
    IO.puts("First 5 values: #{Enum.take(embedding, 5) |> Enum.join(", ")}")

  {:error, error} ->
    IO.puts("Error: #{error.message}")
end

# Example 6: Batch embeddings
IO.puts("\n=== Example 6: Batch Embeddings ===")

texts = ["Hello world", "Goodbye world", "How are you?"]

case Openrouter.embed(texts, model: "text-embedding-3-small") do
  {:ok, embeddings} ->
    IO.puts("Generated #{length(embeddings)} embeddings")

    embeddings
    |> Enum.with_index()
    |> Enum.each(fn {embedding, idx} ->
      IO.puts("Text #{idx + 1}: #{length(embedding)} dimensions")
    end)

  {:error, error} ->
    IO.puts("Error: #{error.message}")
end

IO.puts("\n=== All Examples Complete ===")
