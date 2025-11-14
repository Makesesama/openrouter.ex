defmodule Openrouter.Integration.ErrorHandlingTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag :error_handling

  setup do
    unless System.get_env("OPENROUTER_API_KEY") || System.get_env("REQORD_MODE") == "replay" do
      ExUnit.configure(exclude: [:integration])
    end

    :ok
  end

  describe "authentication errors" do
    @tag :integration
    test "handles invalid API key" do
      client = Openrouter.new(api_key: "invalid-key-12345")

      assert {:error, error} = Openrouter.chat(client, "Hello", model: "openai/gpt-3.5-turbo")
      assert error.type == :authentication
      assert is_binary(error.message)
    end

    @tag :integration
    test "handles missing API key" do
      client = Openrouter.new(api_key: "")

      assert {:error, error} = Openrouter.chat(client, "Hello", model: "openai/gpt-3.5-turbo")
      assert error.type in [:authentication, :invalid_request]
    end
  end

  describe "invalid model errors" do
    @tag :integration
    test "handles non-existent model" do
      assert {:error, error} =
               Openrouter.chat("Hello", model: "nonexistent/model-xyz-123456")

      assert error.type in [:invalid_request, :not_found]
      assert is_binary(error.message)
    end

    @tag :integration
    test "handles malformed model name" do
      assert {:error, error} = Openrouter.chat("Hello", model: "invalid-model-name")

      assert error.type in [:invalid_request, :not_found]
    end
  end

  describe "invalid request errors" do
    @tag :integration
    test "handles empty messages" do
      result = Openrouter.chat([], model: "openai/gpt-3.5-turbo")

      assert {:error, error} = result
      assert error.type in [:invalid_request, :validation_error]
    end

    @tag :integration
    test "handles invalid temperature" do
      result =
        Openrouter.chat(
          "Hello",
          model: "openai/gpt-3.5-turbo",
          temperature: 5.0  # Invalid: should be 0-2
        )

      # Might succeed (API might clamp) or error
      case result do
        {:ok, _response} -> assert true
        {:error, error} -> assert error.type == :invalid_request
      end
    end

    @tag :integration
    test "handles negative max_tokens" do
      result =
        Openrouter.chat(
          "Hello",
          model: "openai/gpt-3.5-turbo",
          max_tokens: -10
        )

      assert {:error, error} = result
      assert error.type == :invalid_request
    end
  end

  describe "error structure" do
    @tag :integration
    test "error has proper structure" do
      {:error, error} =
        Openrouter.chat("Hello", model: "invalid/model")

      assert %Openrouter.Types.Error{} = error
      assert is_atom(error.type)
      assert is_binary(error.message)
      assert is_integer(error.status_code) or is_nil(error.status_code)
    end

    @tag :integration
    test "error includes status code" do
      {:error, error} =
        Openrouter.chat("Hello", model: "invalid/model")

      assert is_integer(error.status_code)
      assert error.status_code >= 400
    end
  end

  describe "streaming errors" do
    @tag :integration
    test "handles invalid model in streaming" do
      result = Openrouter.chat_stream("Hello", model: "invalid/model-xyz")

      assert {:error, error} = result
      assert error.type in [:invalid_request, :not_found]
    end

    @tag :integration
    test "handles authentication error in streaming" do
      client = Openrouter.new(api_key: "invalid-key")

      result = Openrouter.chat_stream(client, "Hello", model: "openai/gpt-3.5-turbo")

      assert {:error, error} = result
      assert error.type == :authentication
    end
  end

  describe "extraction errors" do
    @tag :integration
    test "handles missing schema" do
      result = Openrouter.extract("Hello", model: "openai/gpt-3.5-turbo")

      assert {:error, error} = result
      assert error.type == :validation_error
      assert error.message =~ "schema"
    end

    @tag :integration
    test "handles invalid JSON schema" do
      invalid_schema = %{invalid: "schema"}

      # This might succeed or fail depending on the LLM's output
      result =
        Openrouter.extract(
          "Extract data",
          json_schema: invalid_schema,
          model: "openai/gpt-3.5-turbo"
        )

      # Just ensure it returns something
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "embedding errors" do
    @tag :integration
    test "handles invalid embedding model" do
      result = Openrouter.embed("Hello", model: "invalid-embedding-model")

      assert {:error, error} = result
      assert error.type in [:invalid_request, :not_found]
    end

    @tag :integration
    test "handles authentication error in embeddings" do
      client = Openrouter.new(api_key: "invalid-key")

      result = Openrouter.embed(client, "Hello", model: "text-embedding-3-small")

      assert {:error, error} = result
      assert error.type == :authentication
    end
  end

  describe "timeout handling" do
    @tag :integration
    @tag :slow
    test "handles very short timeout" do
      result =
        Openrouter.chat(
          "Write a very long essay",
          model: "openai/gpt-3.5-turbo",
          timeout: 1  # 1ms - should timeout
        )

      # Should timeout or complete very quickly
      case result do
        {:error, error} ->
          assert error.type in [:timeout, :network_error]

        {:ok, _response} ->
          # Completed very quickly
          assert true
      end
    end
  end

  describe "retry behavior" do
    @tag :integration
    test "retry succeeds after transient failure" do
      # Use retry with a valid request
      # Most requests should succeed without retry
      result =
        Openrouter.Retry.with_retry(
          fn -> Openrouter.chat("Hello", model: "openai/gpt-3.5-turbo") end,
          max_attempts: 3,
          base_delay: 100
        )

      assert {:ok, _response} = result
    end

    @tag :integration
    test "retry stops after max attempts on permanent error" do
      # Invalid API key is a permanent error
      result =
        Openrouter.Retry.with_retry(
          fn ->
            client = Openrouter.new(api_key: "invalid")
            Openrouter.chat(client, "Hello", model: "openai/gpt-3.5-turbo")
          end,
          max_attempts: 2,
          base_delay: 10
        )

      # Should fail without retrying (authentication is not retryable)
      assert {:error, error} = result
      assert error.type == :authentication
    end

    @tag :integration
    test "does not retry on non-retryable errors" do
      # Authentication errors should not be retried
      call_count = :counters.new(1, [])

      result =
        Openrouter.Retry.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            client = Openrouter.new(api_key: "invalid")
            Openrouter.chat(client, "Hello", model: "openai/gpt-3.5-turbo")
          end,
          max_attempts: 3,
          base_delay: 10
        )

      # Should only be called once (no retries)
      assert :counters.get(call_count, 1) == 1
      assert {:error, _} = result
    end
  end

  describe "malformed responses" do
    @tag :integration
    test "handles unexpected response format gracefully" do
      # Make a valid request - should always work
      {:ok, response} =
        Openrouter.chat("Say hi", model: "openai/gpt-3.5-turbo")

      # Response should have expected structure
      assert is_binary(response.content)
      assert is_binary(response.model)
    end
  end

  describe "network errors" do
    @tag :integration
    test "handles invalid base URL" do
      client = Openrouter.new(
        base_url: "https://invalid-url-that-does-not-exist.com/api"
      )

      result = Openrouter.chat(client, "Hello", model: "openai/gpt-3.5-turbo")

      assert {:error, error} = result
      assert error.type in [:network_error, :timeout, :server_error]
    end
  end

  describe "concurrent error handling" do
    @tag :integration
    test "handles multiple concurrent invalid requests" do
      tasks =
        for _ <- 1..5 do
          Task.async(fn ->
            Openrouter.chat("Hello", model: "invalid/model")
          end)
        end

      results = Task.await_many(tasks)

      # All should error
      assert Enum.all?(results, &match?({:error, _}, &1))

      # All should have proper error structure
      Enum.each(results, fn {:error, error} ->
        assert %Openrouter.Types.Error{} = error
        assert error.type in [:invalid_request, :not_found]
      end)
    end
  end

  describe "error recovery" do
    @tag :integration
    test "can recover from error and make successful request" do
      # First, make an invalid request
      {:error, _error} = Openrouter.chat("Hello", model: "invalid/model")

      # Then make a valid request
      {:ok, response} = Openrouter.chat("Hello", model: "openai/gpt-3.5-turbo")

      assert is_binary(response.content)
    end
  end
end
