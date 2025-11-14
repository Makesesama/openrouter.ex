defmodule Openrouter.Types.Message do
  @moduledoc """
  Message types for chat interactions.

  Supports various message roles and content types including text,
  images, videos, and other multimodal content.
  """

  @type role :: :system | :user | :assistant | :tool
  @type content :: String.t() | [content_part()]
  @type content_part ::
          text_content()
          | image_content()
          | video_content()
          | file_content()

  @type text_content :: %{
          type: :text,
          text: String.t()
        }

  @type image_content :: %{
          type: :image_url,
          image_url: %{
            url: String.t(),
            detail: String.t() | nil
          }
        }

  @type video_content :: %{
          type: :video_url,
          video_url: %{
            url: String.t()
          }
        }

  @type file_content :: %{
          type: :file,
          file: %{
            filename: String.t(),
            file_data: String.t()
          }
        }

  @type t :: %__MODULE__{
          role: role(),
          content: content(),
          name: String.t() | nil,
          tool_call_id: String.t() | nil,
          tool_calls: [tool_call()] | nil
        }

  @type tool_call :: %{
          id: String.t(),
          type: String.t(),
          function: %{
            name: String.t(),
            arguments: String.t()
          }
        }

  defstruct [:role, :content, :name, :tool_call_id, :tool_calls]

  @doc """
  Creates a new message.

  ## Examples

      iex> Openrouter.Types.Message.new(:user, "Hello!")
      %Openrouter.Types.Message{role: :user, content: "Hello!"}

      iex> Openrouter.Types.Message.new(:system, "You are a helpful assistant")
      %Openrouter.Types.Message{role: :system, content: "You are a helpful assistant"}
  """
  @spec new(role(), content(), keyword()) :: t()
  def new(role, content, opts \\ []) do
    %__MODULE__{
      role: role,
      content: content,
      name: Keyword.get(opts, :name),
      tool_call_id: Keyword.get(opts, :tool_call_id),
      tool_calls: Keyword.get(opts, :tool_calls)
    }
  end

  @doc """
  Converts a message to the format expected by the API.
  """
  @spec to_api_format(t()) :: map()
  def to_api_format(%__MODULE__{} = message) do
    %{
      role: role_to_string(message.role),
      content: message.content
    }
    |> maybe_add(:name, message.name)
    |> maybe_add(:tool_call_id, message.tool_call_id)
    |> maybe_add(:tool_calls, message.tool_calls)
  end

  @doc """
  Converts a map or message to a Message struct.
  """
  @spec from_api_format(map() | t()) :: t()
  def from_api_format(%__MODULE__{} = message), do: message

  def from_api_format(%{} = map) do
    %__MODULE__{
      role: string_to_role(map["role"] || map[:role]),
      content: map["content"] || map[:content],
      name: map["name"] || map[:name],
      tool_call_id: map["tool_call_id"] || map[:tool_call_id],
      tool_calls: map["tool_calls"] || map[:tool_calls]
    }
  end

  # Private helpers

  defp role_to_string(:system), do: "system"
  defp role_to_string(:user), do: "user"
  defp role_to_string(:assistant), do: "assistant"
  defp role_to_string(:tool), do: "tool"

  defp string_to_role("system"), do: :system
  defp string_to_role("user"), do: :user
  defp string_to_role("assistant"), do: :assistant
  defp string_to_role("tool"), do: :tool
  defp string_to_role(role) when is_atom(role), do: role

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
