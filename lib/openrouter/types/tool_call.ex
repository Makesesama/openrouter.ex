defmodule Openrouter.Types.ToolCall do
  @moduledoc """
  Represents a tool call from an LLM response.

  Tool calls are returned by the LLM when it wants to execute a function.
  The application then executes the function and sends the result back.

  ## Structure

  A tool call contains:
  - `id` - Unique identifier for this tool call
  - `type` - Type of tool (usually "function")
  - `function` - Function details (name and arguments)

  ## Example

      %Openrouter.Types.ToolCall{
        id: "call_abc123",
        type: "function",
        function: %{
          name: "get_weather",
          arguments: "{\"location\": \"Paris\"}"
        }
      }
  """

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          function: %{
            name: String.t(),
            arguments: String.t()
          }
        }

  defstruct [:id, :type, :function]

  @doc """
  Creates a new tool call struct from API format.
  """
  @spec from_api_format(map()) :: t()
  def from_api_format(data) when is_map(data) do
    %__MODULE__{
      id: data["id"] || data[:id],
      type: data["type"] || data[:type] || "function",
      function: %{
        name: get_in(data, ["function", "name"]) || get_in(data, [:function, :name]),
        arguments:
          get_in(data, ["function", "arguments"]) || get_in(data, [:function, :arguments])
      }
    }
  end

  @doc """
  Converts a tool call to API format for sending back to the LLM.
  """
  @spec to_api_format(t()) :: map()
  def to_api_format(%__MODULE__{} = tool_call) do
    %{
      id: tool_call.id,
      type: tool_call.type,
      function: %{
        name: tool_call.function.name,
        arguments: tool_call.function.arguments
      }
    }
  end

  @doc """
  Parses the arguments JSON string into a map.

  Returns `{:ok, map}` on success or `{:error, reason}` if JSON is invalid.

  ## Examples

      iex> tool_call = %Openrouter.Types.ToolCall{
      ...>   id: "call_123",
      ...>   type: "function",
      ...>   function: %{
      ...>     name: "get_weather",
      ...>     arguments: ~s({"location": "Paris"})
      ...>   }
      ...> }
      iex> Openrouter.Types.ToolCall.parse_arguments(tool_call)
      {:ok, %{"location" => "Paris"}}
  """
  @spec parse_arguments(t()) :: {:ok, map()} | {:error, Jason.DecodeError.t()}
  def parse_arguments(%__MODULE__{} = tool_call) do
    Jason.decode(tool_call.function.arguments)
  end

  @doc """
  Parses arguments and converts string keys to atoms.

  Returns `{:ok, map}` with atom keys or `{:error, reason}`.

  ## Examples

      iex> tool_call = %Openrouter.Types.ToolCall{
      ...>   id: "call_123",
      ...>   type: "function",
      ...>   function: %{
      ...>     name: "get_weather",
      ...>     arguments: ~s({"location": "Paris", "unit": "celsius"})
      ...>   }
      ...> }
      iex> Openrouter.Types.ToolCall.parse_arguments_atomized(tool_call)
      {:ok, %{location: "Paris", unit: "celsius"}}
  """
  @spec parse_arguments_atomized(t()) :: {:ok, map()} | {:error, Jason.DecodeError.t()}
  def parse_arguments_atomized(%__MODULE__{} = tool_call) do
    case parse_arguments(tool_call) do
      {:ok, args} ->
        atomized =
          args
          |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
          |> Map.new()

        {:ok, atomized}

      error ->
        error
    end
  end

  @doc """
  Creates a tool result message to send back to the LLM.

  ## Examples

      tool_call = %Openrouter.Types.ToolCall{id: "call_123", ...}
      result = %{temperature: 72, condition: "sunny"}

      message = Openrouter.Types.ToolCall.create_result_message(tool_call, result)
      # => %{role: "tool", tool_call_id: "call_123", content: "..."}
  """
  @spec create_result_message(t(), any()) :: map()
  def create_result_message(%__MODULE__{} = tool_call, result) do
    content =
      case result do
        string when is_binary(string) -> string
        other -> Jason.encode!(other)
      end

    %{
      role: "tool",
      tool_call_id: tool_call.id,
      content: content
    }
  end

  @doc """
  Checks if a tool call has the given function name.

  ## Examples

      tool_call = %Openrouter.Types.ToolCall{
        function: %{name: "get_weather", ...}
      }

      Openrouter.Types.ToolCall.has_function?(tool_call, "get_weather")
      # => true

      Openrouter.Types.ToolCall.has_function?(tool_call, :get_weather)
      # => true
  """
  @spec has_function?(t(), String.t() | atom()) :: boolean()
  def has_function?(%__MODULE__{} = tool_call, function_name) when is_atom(function_name) do
    has_function?(tool_call, to_string(function_name))
  end

  def has_function?(%__MODULE__{} = tool_call, function_name) when is_binary(function_name) do
    tool_call.function.name == function_name
  end

  @doc """
  Extracts all tool calls from a response.

  Returns a list of ToolCall structs.
  """
  @spec from_response(Openrouter.Types.Response.t()) :: [t()]
  def from_response(%Openrouter.Types.Response{tool_calls: nil}), do: []

  def from_response(%Openrouter.Types.Response{tool_calls: tool_calls})
      when is_list(tool_calls) do
    Enum.map(tool_calls, &from_api_format/1)
  end

  @doc """
  Checks if a response contains any tool calls.
  """
  @spec has_tool_calls?(Openrouter.Types.Response.t()) :: boolean()
  def has_tool_calls?(%Openrouter.Types.Response{tool_calls: nil}), do: false
  def has_tool_calls?(%Openrouter.Types.Response{tool_calls: []}), do: false
  def has_tool_calls?(%Openrouter.Types.Response{tool_calls: calls}) when is_list(calls), do: true
end
