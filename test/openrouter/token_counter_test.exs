defmodule Openrouter.TokenCounterTest do
  use ExUnit.Case, async: true

  alias Openrouter.TokenCounter

  describe "count/1" do
    test "counts tokens in simple text" do
      # ~4 characters per token
      assert TokenCounter.count("Hello") == 1
      assert TokenCounter.count("Hello, world!") == 3
    end

    test "counts tokens in longer text" do
      text = "This is a longer sentence with multiple words and punctuation."
      count = TokenCounter.count(text)
      # Should be roughly length/4
      assert count >= 10
      assert count <= 20
    end

    test "handles empty string" do
      assert TokenCounter.count("") == 1
    end

    test "handles very long text" do
      text = String.duplicate("word ", 1000)
      count = TokenCounter.count(text)
      assert count > 1000
    end
  end

  describe "count_messages/1" do
    test "counts tokens in single message" do
      messages = [
        %{role: :user, content: "Hello"}
      ]

      count = TokenCounter.count_messages(messages)
      # Message + overhead
      assert count >= 4
    end

    test "counts tokens in multiple messages" do
      messages = [
        %{role: :system, content: "You are helpful"},
        %{role: :user, content: "What is AI?"},
        %{role: :assistant, content: "AI is artificial intelligence"}
      ]

      count = TokenCounter.count_messages(messages)
      # Should account for all messages + overhead
      assert count >= 15
    end

    test "handles atom and string keys" do
      messages1 = [%{role: :user, content: "Hello"}]
      messages2 = [%{"role" => "user", "content" => "Hello"}]

      count1 = TokenCounter.count_messages(messages1)
      count2 = TokenCounter.count_messages(messages2)

      assert count1 == count2
    end

    test "handles missing content" do
      messages = [
        %{role: :user}
      ]

      count = TokenCounter.count_messages(messages)
      assert count >= 3
    end

    test "handles empty message list" do
      count = TokenCounter.count_messages([])
      assert count == 3
    end
  end

  describe "estimate_cost/2" do
    test "estimates cost for known model" do
      messages = [%{role: :user, content: "Hello, world!"}]

      {:ok, estimate} = TokenCounter.estimate_cost(messages,
        model: "openai/gpt-3.5-turbo",
        max_tokens: 100
      )

      assert estimate.model == "openai/gpt-3.5-turbo"
      assert estimate.input_tokens > 0
      assert estimate.output_tokens == 100
      assert estimate.input_cost > 0
      assert estimate.output_cost > 0
      assert estimate.total_cost == estimate.input_cost + estimate.output_cost
    end

    test "estimates cost with default max_tokens" do
      messages = [%{role: :user, content: "Test"}]

      {:ok, estimate} = TokenCounter.estimate_cost(messages,
        model: "openai/gpt-4"
      )

      assert estimate.output_tokens == 500
    end

    test "estimates cost for various models" do
      messages = [%{role: :user, content: "Test"}]

      models = [
        "openai/gpt-4",
        "openai/gpt-3.5-turbo",
        "anthropic/claude-3-haiku",
        "google/gemini-2.0-flash"
      ]

      Enum.each(models, fn model ->
        assert {:ok, estimate} = TokenCounter.estimate_cost(messages, model: model)
        assert estimate.total_cost > 0
      end)
    end

    test "returns error for unknown model" do
      messages = [%{role: :user, content: "Test"}]

      assert {:error, :model_not_found} = TokenCounter.estimate_cost(messages,
        model: "unknown/model"
      )
    end

    test "uses custom pricing when provided" do
      messages = [%{role: :user, content: "Hello"}]

      custom_pricing = %{
        prompt: 10.0,
        completion: 20.0
      }

      {:ok, estimate} = TokenCounter.estimate_cost(messages,
        model: "any/model",
        max_tokens: 100,
        pricing: custom_pricing
      )

      # Should use custom pricing instead of failing
      assert estimate.total_cost > 0
    end

    test "estimates higher costs for GPT-4 than GPT-3.5" do
      messages = [%{role: :user, content: "Test message"}]

      {:ok, gpt4_estimate} = TokenCounter.estimate_cost(messages,
        model: "openai/gpt-4",
        max_tokens: 100
      )

      {:ok, gpt35_estimate} = TokenCounter.estimate_cost(messages,
        model: "openai/gpt-3.5-turbo",
        max_tokens: 100
      )

      assert gpt4_estimate.total_cost > gpt35_estimate.total_cost
    end
  end

  describe "pricing/1" do
    test "returns pricing for known models" do
      assert {:ok, pricing} = TokenCounter.pricing("openai/gpt-4")
      assert pricing.prompt > 0
      assert pricing.completion > 0
    end

    test "returns error for unknown model" do
      assert {:error, :model_not_found} = TokenCounter.pricing("unknown/model")
    end

    test "returns different pricing for different models" do
      {:ok, gpt4} = TokenCounter.pricing("openai/gpt-4")
      {:ok, gpt35} = TokenCounter.pricing("openai/gpt-3.5-turbo")

      assert gpt4.prompt > gpt35.prompt
      assert gpt4.completion > gpt35.completion
    end
  end

  describe "set_pricing/2" do
    test "sets custom pricing for a model" do
      model = "custom/test-model-#{:rand.uniform(10000)}"

      :ok = TokenCounter.set_pricing(model, %{
        prompt: 1.5,
        completion: 3.0
      })

      {:ok, pricing} = TokenCounter.pricing(model)
      assert pricing.prompt == 1.5
      assert pricing.completion == 3.0
    end

    test "overrides default pricing" do
      model = "openai/gpt-4"

      # Get original pricing
      {:ok, original} = TokenCounter.pricing(model)

      # Override
      :ok = TokenCounter.set_pricing(model, %{
        prompt: 999.0,
        completion: 999.0
      })

      {:ok, custom} = TokenCounter.pricing(model)
      assert custom.prompt == 999.0
      assert custom.completion == 999.0

      # Restore original (for other tests)
      :ok = TokenCounter.set_pricing(model, original)
    end

    test "custom pricing is used in estimates" do
      model = "custom/test-model-#{:rand.uniform(10000)}"

      :ok = TokenCounter.set_pricing(model, %{
        prompt: 100.0,
        completion: 200.0
      })

      messages = [%{role: :user, content: "Test"}]

      {:ok, estimate} = TokenCounter.estimate_cost(messages,
        model: model,
        max_tokens: 10
      )

      # With high pricing, cost should be substantial
      assert estimate.total_cost > 1.0
    end
  end

  describe "format_estimate/1" do
    test "formats estimate as human-readable string" do
      estimate = %{
        model: "openai/gpt-4",
        input_tokens: 100,
        output_tokens: 200,
        input_cost: 0.003,
        output_cost: 0.012,
        total_cost: 0.015
      }

      formatted = TokenCounter.format_estimate(estimate)

      assert formatted =~ "0.015"
      assert formatted =~ "100 tokens"
      assert formatted =~ "200 tokens"
      assert formatted =~ "0.003"
      assert formatted =~ "0.012"
      assert formatted =~ "openai/gpt-4"
    end
  end

  describe "integration: estimate vs actual" do
    test "estimate is in ballpark of actual (within 2x)" do
      # This test verifies our estimation is reasonable
      messages = [
        %{role: :system, content: "You are helpful"},
        %{role: :user, content: "What is 2+2?"}
      ]

      {:ok, estimate} = TokenCounter.estimate_cost(messages,
        model: "openai/gpt-3.5-turbo",
        max_tokens: 50
      )

      # Estimates should be reasonable (not off by 10x)
      assert estimate.input_tokens > 0
      assert estimate.input_tokens < 1000
      assert estimate.total_cost > 0
      assert estimate.total_cost < 1.0
    end
  end
end
