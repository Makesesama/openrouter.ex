defmodule Openrouter.Types.Response do
  @moduledoc """
  Response types from AI model completions.
  """

  alias Openrouter.Types.{Message, Usage}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          model: String.t(),
          content: String.t() | nil,
          role: Message.role(),
          tool_calls: [Message.tool_call()] | nil,
          finish_reason: String.t() | nil,
          usage: Usage.t() | nil,
          metadata: map()
        }

  defstruct [
    :id,
    :model,
    :content,
    :role,
    :tool_calls,
    :finish_reason,
    :usage,
    metadata: %{}
  ]

  @doc """
  Creates a new response struct from API data.
  """
  @spec from_api_format(map()) :: t()
  def from_api_format(data) do
    choice = get_in(data, ["choices", Access.at(0)]) || %{}
    message = choice["message"] || %{}

    %__MODULE__{
      id: data["id"],
      model: data["model"],
      content: message["content"],
      role: parse_role(message["role"]),
      tool_calls: message["tool_calls"],
      finish_reason: choice["finish_reason"],
      usage: parse_usage(data["usage"]),
      metadata: data
    }
  end

  @doc """
  Converts the response to a Message struct.
  """
  @spec to_message(t()) :: Message.t()
  def to_message(%__MODULE__{} = response) do
    Message.new(
      response.role,
      response.content,
      tool_calls: response.tool_calls
    )
  end

  # Private helpers

  defp parse_role("system"), do: :system
  defp parse_role("user"), do: :user
  defp parse_role("assistant"), do: :assistant
  defp parse_role("tool"), do: :tool
  defp parse_role(_), do: :assistant

  defp parse_usage(nil), do: nil

  defp parse_usage(usage) when is_map(usage) do
    Usage.from_api_format(usage)
  end
end
