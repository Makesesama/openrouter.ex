defmodule Openrouter.Integration.ChatCompletionTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag :chat

  setup do
    # Skip if no API key is set and not in replay mode
    unless System.get_env("OPENROUTER_API_KEY") || System.get_env("REQORD_MODE") == "replay" do
      ExUnit.configure(exclude: [:integration])
    end

    :ok
  end

  describe "simple chat completion" do
    @tag :integration
    test "basic text completion" do
      {:ok, response} =
        Openrouter.chat(
          "What is 2+2? Answer with just the number.",
          model: "openai/gpt-3.5-turbo"
        )

      assert is_binary(response.content)
      assert response.content =~ "4"
      assert response.model
      assert response.usage
      assert response.usage.total_tokens > 0
    end

    @tag :integration
    test "completion with system message" do
      messages = [
        %{role: :system, content: "You are a helpful assistant who answers concisely."},
        %{role: :user, content: "What is the capital of France?"}
      ]

      {:ok, response} = Openrouter.chat(messages, model: "openai/gpt-3.5-turbo")

      assert is_binary(response.content)
      assert response.content =~ ~r/Paris/i
    end
  end

  describe "conversation history" do
    @tag :integration
    test "multi-turn conversation" do
      messages = [
        %{role: :system, content: "You are a helpful math tutor"},
        %{role: :user, content: "What is 5+3?"},
        %{role: :assistant, content: "5+3 equals 8"},
        %{role: :user, content: "Now multiply that by 2"}
      ]

      {:ok, response} = Openrouter.chat(messages, model: "openai/gpt-3.5-turbo")

      assert is_binary(response.content)
      assert response.content =~ "16"
    end

    @tag :integration
    test "maintains context across turns" do
      messages = [
        %{role: :user, content: "My name is Alice"},
        %{role: :assistant, content: "Nice to meet you, Alice!"},
        %{role: :user, content: "What is my name?"}
      ]

      {:ok, response} = Openrouter.chat(messages, model: "openai/gpt-3.5-turbo")

      assert response.content =~ ~r/Alice/i
    end
  end

  describe "parameters" do
    @tag :integration
    test "temperature parameter affects output" do
      {:ok, response} =
        Openrouter.chat(
          "Say hello",
          model: "openai/gpt-3.5-turbo",
          temperature: 0.1
        )

      assert is_binary(response.content)
      assert String.length(response.content) > 0
    end

    @tag :integration
    test "max_tokens limits response length" do
      {:ok, response} =
        Openrouter.chat(
          "Write a long essay about artificial intelligence",
          model: "openai/gpt-3.5-turbo",
          max_tokens: 50
        )

      assert is_binary(response.content)
      # Response should be limited by max_tokens
      assert response.usage.completion_tokens <= 50
    end

    @tag :integration
    test "stop sequences work correctly" do
      {:ok, response} =
        Openrouter.chat(
          "Count from 1 to 10",
          model: "openai/gpt-3.5-turbo",
          stop: ["5"]
        )

      assert is_binary(response.content)
      # Should stop before reaching 5
      refute response.content =~ ~r/[6-9]|10/
    end
  end

  describe "client configuration" do
    @tag :integration
    test "uses client-configured model" do
      client = Openrouter.new(model: "openai/gpt-3.5-turbo")

      {:ok, response} = Openrouter.chat(client, "Say hello")

      assert is_binary(response.content)
      assert response.model =~ "gpt-3.5-turbo"
    end

    @tag :integration
    test "client configuration can be overridden" do
      client = Openrouter.new(model: "openai/gpt-3.5-turbo")

      {:ok, response} =
        Openrouter.chat(client, "Say hello", model: "openai/gpt-3.5-turbo")

      assert is_binary(response.content)
      assert response.model =~ "gpt-3.5-turbo"
    end
  end

  describe "response metadata" do
    @tag :integration
    test "includes usage information" do
      {:ok, response} =
        Openrouter.chat("Hello", model: "openai/gpt-3.5-turbo")

      assert response.usage
      assert response.usage.prompt_tokens > 0
      assert response.usage.completion_tokens > 0
      assert response.usage.total_tokens > 0
    end

    @tag :integration
    test "includes finish reason" do
      {:ok, response} =
        Openrouter.chat("Hello", model: "openai/gpt-3.5-turbo")

      assert response.finish_reason in ["stop", "length", nil]
    end

    @tag :integration
    test "includes model information" do
      {:ok, response} =
        Openrouter.chat("Hello", model: "openai/gpt-3.5-turbo")

      assert is_binary(response.model)
      assert response.model =~ "gpt"
    end
  end
end
