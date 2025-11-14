defmodule Openrouter.Types.Usage do
  @moduledoc """
  Token usage and cost information from API responses.

  OpenRouter returns both normalized token counts (using GPT-4o tokenizer) and
  native token counts (using the model's own tokenizer). Billing is based on
  native token counts.

  ## Cost Tracking

  To enable cost tracking in responses, use the `usage` parameter:

      Openrouter.chat(messages,
        model: "openai/gpt-4",
        usage: %{include: true}
      )

  This will populate the cost fields in the usage struct.

  ## Fields

  - `prompt_tokens` - Normalized prompt token count (GPT-4o tokenizer)
  - `completion_tokens` - Normalized completion token count (GPT-4o tokenizer)
  - `total_tokens` - Total normalized tokens
  - `native_tokens_prompt` - Actual prompt tokens (model's native tokenizer, used for billing)
  - `native_tokens_completion` - Actual completion tokens (model's native tokenizer, used for billing)
  - `total_cost` - Total cost in USD for this request
  - `cache_discount` - Discount applied for cached tokens (if any)
  """

  @type t :: %__MODULE__{
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          native_tokens_prompt: non_neg_integer() | nil,
          native_tokens_completion: non_neg_integer() | nil,
          total_cost: float() | nil,
          cache_discount: float() | nil
        }

  defstruct [
    :prompt_tokens,
    :completion_tokens,
    :total_tokens,
    :native_tokens_prompt,
    :native_tokens_completion,
    :total_cost,
    :cache_discount
  ]

  @doc """
  Creates a new usage struct from API data.

  Handles both the standard API response format and the generation endpoint format.
  """
  @spec from_api_format(map()) :: t()
  def from_api_format(data) when is_map(data) do
    %__MODULE__{
      prompt_tokens: data["prompt_tokens"] || 0,
      completion_tokens: data["completion_tokens"] || 0,
      total_tokens: data["total_tokens"] || 0,
      native_tokens_prompt: data["native_tokens_prompt"],
      native_tokens_completion: data["native_tokens_completion"],
      total_cost: parse_cost(data["total_cost"]),
      cache_discount: parse_cost(data["cache_discount"])
    }
  end

  @doc """
  Adds two usage structs together.

  Combines token counts and costs. Note that cache_discount is not summed
  as it represents a percentage or multiplier, not an absolute value.
  """
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{} = u1, %__MODULE__{} = u2) do
    %__MODULE__{
      prompt_tokens: u1.prompt_tokens + u2.prompt_tokens,
      completion_tokens: u1.completion_tokens + u2.completion_tokens,
      total_tokens: u1.total_tokens + u2.total_tokens,
      native_tokens_prompt: add_optional(u1.native_tokens_prompt, u2.native_tokens_prompt),
      native_tokens_completion:
        add_optional(u1.native_tokens_completion, u2.native_tokens_completion),
      total_cost: add_optional(u1.total_cost, u2.total_cost),
      cache_discount: u2.cache_discount || u1.cache_discount
    }
  end

  @doc """
  Formats the usage information as a human-readable string.

  ## Examples

      iex> usage = %Usage{
      ...>   prompt_tokens: 100,
      ...>   completion_tokens: 50,
      ...>   total_cost: 0.00123
      ...> }
      iex> Usage.format(usage)
      "150 tokens (100 prompt + 50 completion) | Cost: $0.00123"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = usage) do
    tokens = "#{usage.total_tokens} tokens (#{usage.prompt_tokens} prompt + #{usage.completion_tokens} completion)"

    cost =
      if usage.total_cost do
        " | Cost: $#{Float.round(usage.total_cost, 6)}"
      else
        ""
      end

    cache =
      if usage.cache_discount do
        " | Cache savings: $#{Float.round(usage.cache_discount, 6)}"
      else
        ""
      end

    tokens <> cost <> cache
  end

  @doc """
  Returns the effective cost after applying cache discount.
  """
  @spec effective_cost(t()) :: float() | nil
  def effective_cost(%__MODULE__{total_cost: nil}), do: nil

  def effective_cost(%__MODULE__{total_cost: cost, cache_discount: nil}), do: cost

  def effective_cost(%__MODULE__{total_cost: cost, cache_discount: discount}) do
    cost - discount
  end

  @doc """
  Returns the native (billing) token count.
  Falls back to normalized count if native count is not available.
  """
  @spec billing_tokens(t()) :: non_neg_integer()
  def billing_tokens(%__MODULE__{} = usage) do
    prompt = usage.native_tokens_prompt || usage.prompt_tokens
    completion = usage.native_tokens_completion || usage.completion_tokens
    prompt + completion
  end

  # Private helpers

  defp parse_cost(nil), do: nil
  defp parse_cost(cost) when is_number(cost), do: cost / 1.0
  defp parse_cost(cost) when is_binary(cost), do: String.to_float(cost)
  defp parse_cost(_), do: nil

  defp add_optional(nil, nil), do: nil
  defp add_optional(nil, v2), do: v2
  defp add_optional(v1, nil), do: v1
  defp add_optional(v1, v2), do: v1 + v2
end
