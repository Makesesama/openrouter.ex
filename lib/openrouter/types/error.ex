defmodule Openrouter.Types.Error do
  @moduledoc """
  Error types for the Openrouter library.
  """

  @type error_type ::
          :rate_limit
          | :invalid_request
          | :authentication
          | :permission_denied
          | :not_found
          | :server_error
          | :timeout
          | :network_error
          | :provider_error
          | :validation_error
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          retry_after: non_neg_integer() | nil,
          status_code: integer() | nil,
          original: any()
        }

  defstruct [:type, :message, :retry_after, :status_code, :original]

  @doc """
  Creates a new error struct.
  """
  @spec new(error_type(), String.t(), keyword()) :: t()
  def new(type, message, opts \\ []) do
    %__MODULE__{
      type: type,
      message: message,
      retry_after: Keyword.get(opts, :retry_after),
      status_code: Keyword.get(opts, :status_code),
      original: Keyword.get(opts, :original)
    }
  end

  @doc """
  Creates an error from an HTTP response.
  """
  @spec from_http_response(Req.Response.t() | map()) :: t()
  def from_http_response(%{status: status, body: body}) do
    type = status_to_type(status)
    message = extract_message(body)
    retry_after = extract_retry_after(body)

    new(type, message,
      status_code: status,
      retry_after: retry_after,
      original: body
    )
  end

  @doc """
  Creates an error from an exception.
  """
  @spec from_exception(Exception.t()) :: t()
  def from_exception(%_{} = exception) do
    new(:network_error, Exception.message(exception), original: exception)
  end

  # Private helpers

  defp status_to_type(429), do: :rate_limit
  defp status_to_type(400), do: :invalid_request
  defp status_to_type(401), do: :authentication
  defp status_to_type(403), do: :permission_denied
  defp status_to_type(404), do: :not_found
  defp status_to_type(status) when status >= 500, do: :server_error
  defp status_to_type(_), do: :unknown

  defp extract_message(body) when is_map(body) do
    body["error"]["message"] || body["error"] || body["message"] || "Unknown error"
  end

  defp extract_message(body) when is_binary(body), do: body
  defp extract_message(_), do: "Unknown error"

  defp extract_retry_after(body) when is_map(body) do
    body["retry_after"]
  end

  defp extract_retry_after(_), do: nil
end
