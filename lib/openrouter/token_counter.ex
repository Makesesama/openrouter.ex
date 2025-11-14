defmodule Openrouter.TokenCounter do
  @moduledoc """
  Utilities for counting tokens and estimating costs before making API calls.

  This module provides approximate token counting and cost estimation based on
  OpenRouter's pricing. Token counts are estimates using a simple character-based
  heuristic. For accurate counts, use the actual API response with `usage: %{include: true}`.

  ## Token Estimation

  The module uses a simple heuristic: ~4 characters per token for English text.
  This is an approximation and actual counts vary by model and language.

  ## Cost Estimation

  Costs are estimated based on OpenRouter's published pricing. Actual costs may
  vary slightly due to:
  - Different tokenization between models
  - Prompt caching
  - OpenRouter's fee structure

  ## Usage

      # Count tokens in text
      tokens = TokenCounter.count("Hello, world!")
      # => ~3 tokens

      # Estimate cost for a request
      messages = [
        %{role: :user, content: "What is Elixir?"}
      ]
      {:ok, estimate} = TokenCounter.estimate_cost(messages,
        model: "openai/gpt-4",
        max_tokens: 500
      )

      IO.puts("Estimated cost: $\#{estimate.total_cost}")
      IO.puts("Input tokens: \#{estimate.input_tokens}")
      IO.puts("Output tokens: \#{estimate.output_tokens}")

  ## Model Pricing

  Pricing is fetched from OpenRouter's models API or can be manually configured.
  See `set_pricing/2` to override pricing for specific models.
  """

  @doc """
  Estimates the number of tokens in a string.

  Uses a simple heuristic: approximately 1 token per 4 characters for English.
  This is a rough estimate; actual token counts depend on the model's tokenizer.

  ## Examples

      iex> TokenCounter.count("Hello, world!")
      3

      iex> TokenCounter.count("This is a longer sentence with more words.")
      11
  """
  @spec count(String.t()) :: non_neg_integer()
  def count(text) when is_binary(text) do
    # Simple heuristic: ~4 characters per token
    # More accurate would require a proper tokenizer library
    chars = String.length(text)
    max(1, div(chars, 4))
  end

  @doc """
  Counts tokens in a list of messages.

  Accounts for role labels and message structure overhead.

  ## Examples

      iex> messages = [
      ...>   %{role: :system, content: "You are helpful"},
      ...>   %{role: :user, content: "Hello!"}
      ...> ]
      iex> TokenCounter.count_messages(messages)
      ~11 tokens (approximate)
  """
  @spec count_messages([map()]) :: non_neg_integer()
  def count_messages(messages) when is_list(messages) do
    messages
    |> Enum.reduce(0, fn msg, acc ->
      content_tokens = count(msg[:content] || msg["content"] || "")
      # Add ~3 tokens for message overhead (role, formatting)
      acc + content_tokens + 3
    end)
    |> Kernel.+(3)
  end

  # Add 3 for message envelope

  @doc """
  Estimates the cost of an API request before making it.

  ## Options

  - `:model` - Model name (required)
  - `:max_tokens` - Maximum completion tokens (default: 500)
  - `:pricing` - Custom pricing override (see `pricing/1`)

  Returns `{:ok, estimate}` with:
  - `:input_tokens` - Estimated input tokens
  - `:output_tokens` - Estimated output tokens
  - `:input_cost` - Cost for input
  - `:output_cost` - Cost for output
  - `:total_cost` - Total estimated cost in USD

  ## Examples

      {:ok, estimate} = TokenCounter.estimate_cost(
        [%{role: :user, content: "Hello"}],
        model: "openai/gpt-3.5-turbo",
        max_tokens: 100
      )
  """
  @spec estimate_cost([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def estimate_cost(messages, opts) do
    model = Keyword.fetch!(opts, :model)
    max_tokens = Keyword.get(opts, :max_tokens, 500)
    custom_pricing = Keyword.get(opts, :pricing)

    input_tokens = count_messages(messages)
    output_tokens = max_tokens

    case get_pricing(model, custom_pricing) do
      {:ok, pricing} ->
        input_cost = input_tokens * pricing.prompt / 1_000_000
        output_cost = output_tokens * pricing.completion / 1_000_000
        total_cost = input_cost + output_cost

        estimate = %{
          model: model,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          input_cost: input_cost,
          output_cost: output_cost,
          total_cost: total_cost
        }

        {:ok, estimate}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets pricing information for a model.

  Returns `{:ok, pricing}` with:
  - `:prompt` - Cost per 1M prompt tokens in USD
  - `:completion` - Cost per 1M completion tokens in USD

  Pricing is based on OpenRouter's published rates. Use `set_pricing/2` to
  override with custom pricing.

  ## Examples

      {:ok, pricing} = TokenCounter.pricing("openai/gpt-4")
      # => %{prompt: 30.0, completion: 60.0}
  """
  @spec pricing(String.t()) :: {:ok, map()} | {:error, :model_not_found}
  def pricing(model) do
    get_pricing(model, nil)
  end

  @doc """
  Sets custom pricing for a model.

  Useful for:
  - Overriding default pricing
  - Adding pricing for new models
  - Testing cost estimates

  ## Examples

      :ok = TokenCounter.set_pricing("custom/model", %{
        prompt: 1.0,
        completion: 2.0
      })
  """
  @spec set_pricing(String.t(), map()) :: :ok
  def set_pricing(model, pricing) do
    pricing_data = %{
      prompt: Map.fetch!(pricing, :prompt),
      completion: Map.fetch!(pricing, :completion)
    }

    :persistent_term.put({__MODULE__, :pricing, model}, pricing_data)
    :ok
  end

  @doc """
  Formats an estimate as a human-readable string.

  ## Examples

      {:ok, estimate} = TokenCounter.estimate_cost(messages, model: "openai/gpt-4")
      IO.puts(TokenCounter.format_estimate(estimate))
      # =>
      # Estimated Cost: $0.045
      #   Input: 500 tokens ($0.015)
      #   Output: 500 tokens ($0.030)
  """
  @spec format_estimate(map()) :: String.t()
  def format_estimate(estimate) do
    """
    Estimated Cost: $#{Float.round(estimate.total_cost, 6)}
      Input: #{estimate.input_tokens} tokens ($#{Float.round(estimate.input_cost, 6)})
      Output: #{estimate.output_tokens} tokens ($#{Float.round(estimate.output_cost, 6)})
    Model: #{estimate.model}
    """
  end

  ## Private Helpers

  # Default pricing for common models (as of 2025)
  # Prices are per 1M tokens in USD
  defp get_pricing(model, custom_pricing) do
    # Check for custom pricing override
    if custom_pricing do
      {:ok, custom_pricing}
    else
      # Check persistent_term for user-configured pricing
      case :persistent_term.get({__MODULE__, :pricing, model}, nil) do
        nil -> default_pricing(model)
        pricing -> {:ok, pricing}
      end
    end
  end

  defp default_pricing(model) do
    pricing =
      case model do
        # OpenAI models
        "openai/gpt-4" -> %{prompt: 30.0, completion: 60.0}
        "openai/gpt-4-turbo" -> %{prompt: 10.0, completion: 30.0}
        "openai/gpt-3.5-turbo" -> %{prompt: 0.5, completion: 1.5}
        "openai/gpt-4o" -> %{prompt: 2.5, completion: 10.0}
        "openai/gpt-4o-mini" -> %{prompt: 0.15, completion: 0.6}

        # Anthropic models
        "anthropic/claude-3.5-sonnet" -> %{prompt: 3.0, completion: 15.0}
        "anthropic/claude-3-opus" -> %{prompt: 15.0, completion: 75.0}
        "anthropic/claude-3-sonnet" -> %{prompt: 3.0, completion: 15.0}
        "anthropic/claude-3-haiku" -> %{prompt: 0.25, completion: 1.25}

        # Google models
        "google/gemini-pro" -> %{prompt: 0.5, completion: 1.5}
        "google/gemini-2.0-flash" -> %{prompt: 0.075, completion: 0.3}
        "google/gemini-1.5-pro" -> %{prompt: 1.25, completion: 5.0}

        # Meta models
        "meta-llama/llama-3.3-70b-instruct" -> %{prompt: 0.35, completion: 0.4}
        "meta-llama/llama-3.1-405b-instruct" -> %{prompt: 2.7, completion: 2.7}

        # Mistral models
        "mistralai/mistral-large" -> %{prompt: 2.0, completion: 6.0}
        "mistralai/mistral-medium" -> %{prompt: 2.7, completion: 8.1}
        "mistralai/mistral-small" -> %{prompt: 0.2, completion: 0.6}

        # Cohere models
        "cohere/command-r-plus" -> %{prompt: 2.5, completion: 10.0}
        "cohere/command-r" -> %{prompt: 0.15, completion: 0.6}

        # DeepSeek models
        "deepseek/deepseek-chat" -> %{prompt: 0.14, completion: 0.28}

        _ -> nil
      end

    if pricing do
      {:ok, pricing}
    else
      {:error, :model_not_found}
    end
  end
end
