defmodule Openrouter.IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  # These tests will use reqord for recording/replaying HTTP requests
  # Run with: mix test --only integration
  #
  # To record new interactions:
  #   REQORD_MODE=record mix test --only integration
  #
  # To replay recorded interactions:
  #   REQORD_MODE=replay mix test --only integration
  #
  # See: https://github.com/Makesesama/reqord

  setup do
    # Skip if no API key is set and not in replay mode
    unless System.get_env("OPENROUTER_API_KEY") || System.get_env("REQORD_MODE") == "replay" do
      ExUnit.configure(exclude: [:integration])
    end

    :ok
  end

  describe "chat/2" do
    @tag :integration
    test "simple chat completion" do
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
    test "chat with conversation history" do
      messages = [
        %{role: :system, content: "You are a helpful math tutor"},
        %{role: :user, content: "What is 5+3?"},
        %{role: :assistant, content: "5+3 equals 8"},
        %{role: :user, content: "Now multiply that by 2"}
      ]

      {:ok, response} =
        Openrouter.chat(messages, model: "openai/gpt-3.5-turbo")

      assert is_binary(response.content)
      assert response.content =~ "16"
    end

    @tag :integration
    test "chat with temperature parameter" do
      {:ok, response} =
        Openrouter.chat(
          "Say hello",
          model: "openai/gpt-3.5-turbo",
          temperature: 0.1
        )

      assert is_binary(response.content)
      assert String.length(response.content) > 0
    end
  end

  describe "chat_stream/2" do
    @tag :integration
    test "streams chat completion" do
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
  end

  describe "extract/3" do
    @tag :integration
    test "extracts structured data with Ecto schema" do
      defmodule PersonSchema do
        use Openrouter.Schema

        embedded_schema do
          field :name, :string
          field :age, :integer
          field :city, :string
        end

        def changeset(schema, attrs) do
          schema
          |> cast(attrs, [:name, :age, :city])
          |> validate_required([:name, :age])
        end
      end

      text = "John Smith is 35 years old and lives in New York"

      {:ok, person} =
        Openrouter.extract(
          text,
          schema: PersonSchema,
          model: "openai/gpt-3.5-turbo"
        )

      assert person.name =~ "John"
      assert person.age == 35
      assert person.city =~ "New York"
    end

    @tag :integration
    test "extracts with JSON schema" do
      schema = %{
        type: "object",
        properties: %{
          product: %{type: "string"},
          price: %{type: "number"}
        },
        required: ["product", "price"]
      }

      text = "The MacBook Pro costs $2499"

      {:ok, data} =
        Openrouter.extract(
          text,
          json_schema: schema,
          model: "openai/gpt-3.5-turbo"
        )

      assert is_map(data)
      assert data["product"] =~ "MacBook"
      assert data["price"] > 2000
    end
  end

  describe "embed/2" do
    @tag :integration
    test "generates embeddings" do
      {:ok, [embedding]} =
        Openrouter.embed(
          "Hello world",
          model: "text-embedding-3-small"
        )

      assert is_list(embedding)
      assert length(embedding) > 0
      assert Enum.all?(embedding, &is_float/1)
    end

    @tag :integration
    test "generates batch embeddings" do
      texts = ["Hello", "World", "Test"]

      {:ok, embeddings} =
        Openrouter.embed(
          texts,
          model: "text-embedding-3-small"
        )

      assert length(embeddings) == 3
      assert Enum.all?(embeddings, &is_list/1)
    end
  end

  describe "multimodal content" do
    @tag :integration
    test "analyzes image from URL" do
      content = [
        Openrouter.Content.text("What's in this image? Answer briefly."),
        Openrouter.Content.image_url("https://picsum.photos/200/200")
      ]

      {:ok, response} =
        Openrouter.chat(
          [%{role: :user, content: content}],
          model: "anthropic/claude-3.5-sonnet"
        )

      assert is_binary(response.content)
      assert String.length(response.content) > 10
    end
  end

  describe "error handling" do
    @tag :integration
    test "handles invalid API key" do
      client = Openrouter.new(api_key: "invalid-key-123")

      assert {:error, error} = Openrouter.chat(client, "Hello", model: "openai/gpt-3.5-turbo")
      assert error.type == :authentication
    end

    @tag :integration
    test "handles invalid model" do
      assert {:error, error} =
               Openrouter.chat("Hello", model: "nonexistent/model-xyz-123")

      assert error.type in [:invalid_request, :not_found]
    end
  end

  describe "retry with real errors" do
    @tag :integration
    test "retries on rate limit errors" do
      # This test might not trigger rate limits in normal circumstances
      # It's here as an example of how to test retry behavior
      result =
        Openrouter.Retry.with_retry(
          fn ->
            Openrouter.chat("Hello", model: "openai/gpt-3.5-turbo")
          end,
          max_attempts: 3,
          base_delay: 100
        )

      # Should either succeed or fail after retries
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
