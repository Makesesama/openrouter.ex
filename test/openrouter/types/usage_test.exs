defmodule Openrouter.Types.UsageTest do
  use ExUnit.Case, async: true

  alias Openrouter.Types.Usage

  describe "from_api_format/1" do
    test "parses basic usage data" do
      data = %{
        "prompt_tokens" => 10,
        "completion_tokens" => 20,
        "total_tokens" => 30
      }

      usage = Usage.from_api_format(data)

      assert usage.prompt_tokens == 10
      assert usage.completion_tokens == 20
      assert usage.total_tokens == 30
      assert usage.total_cost == nil
    end

    test "parses usage data with cost information" do
      data = %{
        "prompt_tokens" => 100,
        "completion_tokens" => 200,
        "total_tokens" => 300,
        "native_tokens_prompt" => 105,
        "native_tokens_completion" => 210,
        "total_cost" => 0.045,
        "cache_discount" => 0.005
      }

      usage = Usage.from_api_format(data)

      assert usage.prompt_tokens == 100
      assert usage.completion_tokens == 200
      assert usage.total_tokens == 300
      assert usage.native_tokens_prompt == 105
      assert usage.native_tokens_completion == 210
      assert usage.total_cost == 0.045
      assert usage.cache_discount == 0.005
    end

    test "handles missing optional fields" do
      data = %{
        "prompt_tokens" => 50,
        "completion_tokens" => 50,
        "total_tokens" => 100
      }

      usage = Usage.from_api_format(data)

      assert usage.native_tokens_prompt == nil
      assert usage.native_tokens_completion == nil
      assert usage.total_cost == nil
      assert usage.cache_discount == nil
    end

    test "handles cost as string" do
      data = %{
        "prompt_tokens" => 10,
        "completion_tokens" => 10,
        "total_tokens" => 20,
        "total_cost" => "0.123"
      }

      usage = Usage.from_api_format(data)
      assert usage.total_cost == 0.123
    end

    test "handles cost as integer" do
      data = %{
        "prompt_tokens" => 10,
        "completion_tokens" => 10,
        "total_tokens" => 20,
        "total_cost" => 5
      }

      usage = Usage.from_api_format(data)
      assert usage.total_cost == 5.0
    end
  end

  describe "add/2" do
    test "adds two usage structs" do
      u1 = %Usage{
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30,
        total_cost: 0.001
      }

      u2 = %Usage{
        prompt_tokens: 15,
        completion_tokens: 25,
        total_tokens: 40,
        total_cost: 0.002
      }

      result = Usage.add(u1, u2)

      assert result.prompt_tokens == 25
      assert result.completion_tokens == 45
      assert result.total_tokens == 70
      assert result.total_cost == 0.003
    end

    test "adds native token counts" do
      u1 = %Usage{
        prompt_tokens: 100,
        completion_tokens: 100,
        total_tokens: 200,
        native_tokens_prompt: 105,
        native_tokens_completion: 110
      }

      u2 = %Usage{
        prompt_tokens: 200,
        completion_tokens: 200,
        total_tokens: 400,
        native_tokens_prompt: 210,
        native_tokens_completion: 220
      }

      result = Usage.add(u1, u2)

      assert result.native_tokens_prompt == 315
      assert result.native_tokens_completion == 330
    end

    test "handles nil costs" do
      u1 = %Usage{prompt_tokens: 10, completion_tokens: 10, total_tokens: 20, total_cost: nil}
      u2 = %Usage{prompt_tokens: 10, completion_tokens: 10, total_tokens: 20, total_cost: 0.001}

      result = Usage.add(u1, u2)
      assert result.total_cost == 0.001
    end

    test "handles nil native tokens" do
      u1 = %Usage{
        prompt_tokens: 10,
        completion_tokens: 10,
        total_tokens: 20,
        native_tokens_prompt: nil,
        native_tokens_completion: nil
      }

      u2 = %Usage{
        prompt_tokens: 10,
        completion_tokens: 10,
        total_tokens: 20,
        native_tokens_prompt: 15,
        native_tokens_completion: 15
      }

      result = Usage.add(u1, u2)
      assert result.native_tokens_prompt == 15
      assert result.native_tokens_completion == 15
    end

    test "takes latest cache_discount" do
      u1 = %Usage{
        prompt_tokens: 10,
        completion_tokens: 10,
        total_tokens: 20,
        cache_discount: 0.001
      }

      u2 = %Usage{
        prompt_tokens: 10,
        completion_tokens: 10,
        total_tokens: 20,
        cache_discount: 0.002
      }

      result = Usage.add(u1, u2)
      assert result.cache_discount == 0.002
    end
  end

  describe "format/1" do
    test "formats basic usage" do
      usage = %Usage{
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150
      }

      formatted = Usage.format(usage)
      assert formatted =~ "150 tokens"
      assert formatted =~ "100 prompt"
      assert formatted =~ "50 completion"
    end

    test "formats usage with cost" do
      usage = %Usage{
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150,
        total_cost: 0.00123
      }

      formatted = Usage.format(usage)
      assert formatted =~ "150 tokens"
      assert formatted =~ "$0.00123"
    end

    test "formats usage with cache savings" do
      usage = %Usage{
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150,
        total_cost: 0.005,
        cache_discount: 0.001
      }

      formatted = Usage.format(usage)
      assert formatted =~ "Cache savings"
      assert formatted =~ "$0.001"
    end
  end

  describe "effective_cost/1" do
    test "returns nil when no cost" do
      usage = %Usage{prompt_tokens: 10, completion_tokens: 10, total_tokens: 20}
      assert Usage.effective_cost(usage) == nil
    end

    test "returns total cost when no discount" do
      usage = %Usage{
        prompt_tokens: 10,
        completion_tokens: 10,
        total_tokens: 20,
        total_cost: 0.005
      }

      assert Usage.effective_cost(usage) == 0.005
    end

    test "returns cost minus discount" do
      usage = %Usage{
        prompt_tokens: 10,
        completion_tokens: 10,
        total_tokens: 20,
        total_cost: 0.010,
        cache_discount: 0.002
      }

      assert Usage.effective_cost(usage) == 0.008
    end
  end

  describe "billing_tokens/1" do
    test "returns native tokens when available" do
      usage = %Usage{
        prompt_tokens: 100,
        completion_tokens: 100,
        total_tokens: 200,
        native_tokens_prompt: 105,
        native_tokens_completion: 110
      }

      assert Usage.billing_tokens(usage) == 215
    end

    test "falls back to normalized tokens" do
      usage = %Usage{
        prompt_tokens: 100,
        completion_tokens: 100,
        total_tokens: 200
      }

      assert Usage.billing_tokens(usage) == 200
    end

    test "handles mixed native/normalized tokens" do
      usage = %Usage{
        prompt_tokens: 100,
        completion_tokens: 100,
        total_tokens: 200,
        native_tokens_prompt: 105,
        native_tokens_completion: nil
      }

      # Uses native for prompt, normalized for completion
      assert Usage.billing_tokens(usage) == 205
    end
  end
end
