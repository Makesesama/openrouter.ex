defmodule Openrouter.Types.Usage do
  @moduledoc """
  Token usage information from API responses.
  """

  @type t :: %__MODULE__{
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          total_tokens: non_neg_integer()
        }

  defstruct [:prompt_tokens, :completion_tokens, :total_tokens]

  @doc """
  Creates a new usage struct from API data.
  """
  @spec from_api_format(map()) :: t()
  def from_api_format(data) when is_map(data) do
    %__MODULE__{
      prompt_tokens: data["prompt_tokens"] || 0,
      completion_tokens: data["completion_tokens"] || 0,
      total_tokens: data["total_tokens"] || 0
    }
  end

  @doc """
  Adds two usage structs together.
  """
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{} = u1, %__MODULE__{} = u2) do
    %__MODULE__{
      prompt_tokens: u1.prompt_tokens + u2.prompt_tokens,
      completion_tokens: u1.completion_tokens + u2.completion_tokens,
      total_tokens: u1.total_tokens + u2.total_tokens
    }
  end
end
