defmodule Openrouter.Integration.StreamingTest do
  use Reqord.Case

  @moduletag :integration
  @moduletag :streaming

  describe "basic streaming" do
    @tag :integration
    test "streams chat completion chunks" do
      {:ok, stream} =
        Openrouter.chat_stream(
          "Count from 1 to 3",
          model: "openai/gpt-3.5-turbo"
        )

      chunks =
        stream
        |> Enum.take(20)
        |> Enum.filter(&(&1[:type] == :content))
        |> Enum.map(& &1[:content])

      assert length(chunks) > 0
      content = Enum.join(chunks, "")
      assert String.length(content) > 0
    end

    @tag :skip_reqord
    test "stream includes content chunks" do
      {:ok, stream} =
        Openrouter.chat_stream(
          "Say hello",
          model: "openai/gpt-3.5-turbo"
        )

      events = Enum.to_list(stream)

      content_chunks = Enum.filter(events, &(&1[:type] == :content))
      assert length(content_chunks) > 0

      # All content chunks should have content field
      Enum.each(content_chunks, fn chunk ->
        assert is_binary(chunk[:content])
      end)
    end

    @tag :skip_reqord
    test "stream ends with done event" do
      {:ok, stream} =
        Openrouter.chat_stream(
          "Say hi",
          model: "openai/gpt-3.5-turbo"
        )

      events = Enum.to_list(stream)

      # Should have at least one done event
      done_events = Enum.filter(events, &(&1[:type] == :done))
      assert length(done_events) > 0
    end
  end

  describe "streaming with parameters" do
    @tag :skip_reqord
    test "respects temperature in streaming" do
      {:ok, stream} =
        Openrouter.chat_stream(
          "Say hello",
          model: "openai/gpt-3.5-turbo",
          temperature: 0.1
        )

      events = Enum.to_list(stream)
      content_chunks = Enum.filter(events, &(&1[:type] == :content))

      assert length(content_chunks) > 0
    end

    @tag :skip_reqord
    test "respects max_tokens in streaming" do
      {:ok, stream} =
        Openrouter.chat_stream(
          "Write a very long story",
          model: "openai/gpt-3.5-turbo",
          max_tokens: 20
        )

      events = Enum.to_list(stream)
      content_chunks = Enum.filter(events, &(&1[:type] == :content))

      # Should have chunks but limited by max_tokens
      assert length(content_chunks) > 0

      total_content = Enum.map_join(content_chunks, "", & &1[:content])

      # Rough check that it's limited
      word_count = length(String.split(total_content))
      assert word_count < 50
    end
  end

  describe "streaming with conversation history" do
    @tag :skip_reqord
    test "streams with conversation context" do
      messages = [
        %{role: :user, content: "My favorite color is blue"},
        %{role: :assistant, content: "That's nice!"},
        %{role: :user, content: "What is my favorite color?"}
      ]

      {:ok, stream} = Openrouter.chat_stream(messages, model: "openai/gpt-3.5-turbo")

      events = Enum.to_list(stream)
      content_chunks = Enum.filter(events, &(&1[:type] == :content))

      full_response = Enum.map_join(content_chunks, "", & &1[:content])

      assert full_response =~ ~r/blue/i
    end
  end

  describe "stream event types" do
    @tag :skip_reqord
    test "emits proper event structure" do
      {:ok, stream} =
        Openrouter.chat_stream(
          "Hi",
          model: "openai/gpt-3.5-turbo"
        )

      events = Enum.to_list(stream)

      # Check content events have proper structure
      content_events = Enum.filter(events, &(&1[:type] == :content))

      Enum.each(content_events, fn event ->
        assert event[:type] == :content
        assert is_binary(event[:content])
      end)

      # Check done events have proper structure
      done_events = Enum.filter(events, &(&1[:type] == :done))

      Enum.each(done_events, fn event ->
        assert event[:type] == :done
      end)
    end
  end

  describe "stream processing" do
    @tag :skip_reqord
    test "can be processed with Stream functions" do
      {:ok, stream} =
        Openrouter.chat_stream(
          "Count to 3",
          model: "openai/gpt-3.5-turbo"
        )

      # Test that we can use Stream functions
      result =
        stream
        |> Stream.filter(&(&1[:type] == :content))
        |> Stream.map(& &1[:content])
        |> Enum.to_list()

      assert is_list(result)
      assert length(result) > 0
    end

    @tag :skip_reqord
    test "can accumulate streamed content" do
      {:ok, stream} =
        Openrouter.chat_stream(
          "Say hello world",
          model: "openai/gpt-3.5-turbo"
        )

      accumulated =
        stream
        |> Stream.filter(&(&1[:type] == :content))
        |> Stream.map(& &1[:content])
        |> Enum.reduce("", fn chunk, acc -> acc <> chunk end)

      assert is_binary(accumulated)
      assert String.length(accumulated) > 0
    end
  end

  describe "streaming error handling" do
    @tag :integration
    test "handles invalid model in streaming" do
      result = Openrouter.chat_stream("Hello", model: "invalid/model-xyz")

      assert {:error, error} = result
      assert error.type in [:invalid_request, :not_found]
    end
  end

  describe "streaming with client" do
    @tag :skip_reqord
    test "uses client configuration for streaming" do
      client = Openrouter.new(model: "openai/gpt-3.5-turbo")

      {:ok, stream} = Openrouter.chat_stream(client, "Hello")

      events = Enum.to_list(stream)
      content_chunks = Enum.filter(events, &(&1[:type] == :content))

      assert length(content_chunks) > 0
    end
  end
end
