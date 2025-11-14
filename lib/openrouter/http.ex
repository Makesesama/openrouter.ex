defmodule Openrouter.HTTP do
  @moduledoc """
  HTTP client wrapper using Req.

  Provides a unified interface for making HTTP requests to AI providers
  with proper error handling, telemetry, and streaming support.
  """

  alias Openrouter.Types.Error

  @doc """
  Makes an HTTP request.

  ## Options

    * `:method` - HTTP method (default: :post)
    * `:url` - Full URL or path (required)
    * `:headers` - Additional headers (default: [])
    * `:json` - JSON body
    * `:timeout` - Request timeout in milliseconds

  ## Examples

      iex> Openrouter.HTTP.request(
      ...>   url: "https://api.example.com/v1/chat",
      ...>   json: %{model: "gpt-4", messages: [...]},
      ...>   headers: [{"authorization", "Bearer sk-..."}]
      ...> )
      {:ok, %{status: 200, body: %{...}}}
  """
  @spec request(keyword()) :: {:ok, map()} | {:error, Error.t()}
  def request(opts) do
    method = Keyword.get(opts, :method, :post)
    url = Keyword.fetch!(opts, :url)
    headers = Keyword.get(opts, :headers, [])
    json = Keyword.get(opts, :json)
    timeout = Keyword.get(opts, :timeout, 60_000)

    # Emit telemetry start event
    start_time = System.monotonic_time()

    metadata = %{
      method: method,
      url: url,
      model: json && json[:model]
    }

    :telemetry.execute(
      [:openrouter, :request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    request_opts = [
      method: method,
      url: url,
      headers: headers,
      receive_timeout: timeout
    ]

    request_opts = if json, do: Keyword.put(request_opts, :json, json), else: request_opts

    result =
      case Req.request(request_opts) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          {:ok, body}

        {:ok, response} ->
          {:error, Error.from_http_response(response)}

        {:error, exception} ->
          {:error, Error.from_exception(exception)}
      end

    # Emit telemetry stop/exception event
    duration = System.monotonic_time() - start_time

    case result do
      {:ok, body} ->
        usage = body["usage"]

        :telemetry.execute(
          [:openrouter, :request, :stop],
          %{duration: duration},
          Map.merge(metadata, %{
            status: :ok,
            tokens: usage,
            model: body["model"]
          })
        )

      {:error, error} ->
        :telemetry.execute(
          [:openrouter, :request, :exception],
          %{duration: duration},
          Map.merge(metadata, %{
            error_type: error.type,
            error_message: error.message,
            status_code: error.status_code
          })
        )
    end

    result
  end

  @doc """
  Makes a streaming HTTP request.

  Returns a stream of Server-Sent Events (SSE) chunks.

  ## Options

    * `:url` - Full URL or path (required)
    * `:headers` - Additional headers (default: [])
    * `:json` - JSON body
    * `:timeout` - Request timeout in milliseconds

  ## Examples

      iex> {:ok, stream} = Openrouter.HTTP.request_stream(
      ...>   url: "https://api.example.com/v1/chat",
      ...>   json: %{model: "gpt-4", messages: [...], stream: true}
      ...> )
      iex> Enum.take(stream, 5)
      [%{data: "chunk1"}, %{data: "chunk2"}, ...]
  """
  @spec request_stream(keyword()) :: {:ok, Enumerable.t()} | {:error, Error.t()}
  def request_stream(opts) do
    url = Keyword.fetch!(opts, :url)
    headers = Keyword.get(opts, :headers, [])
    json = Keyword.get(opts, :json)
    timeout = Keyword.get(opts, :timeout, 60_000)

    # Emit telemetry start event
    start_time = System.monotonic_time()

    metadata = %{
      method: :post,
      url: url,
      model: json && json[:model],
      streaming: true
    }

    :telemetry.execute(
      [:openrouter, :stream, :start],
      %{system_time: System.system_time()},
      metadata
    )

    # Ensure stream parameter is set
    json = if json, do: Map.put(json, :stream, true), else: %{stream: true}

    request_opts = [
      method: :post,
      url: url,
      headers: headers,
      json: json,
      receive_timeout: timeout,
      into: :self
    ]

    try do
      response = Req.request!(request_opts)

      stream =
        Stream.resource(
          fn -> {response, start_time, metadata, 0} end,
          &process_stream_chunk/1,
          fn {_response, start_time, metadata, chunk_count} ->
            # Emit stop event when stream completes
            duration = System.monotonic_time() - start_time

            :telemetry.execute(
              [:openrouter, :stream, :stop],
              %{duration: duration, chunk_count: chunk_count},
              metadata
            )
          end
        )

      {:ok, stream}
    rescue
      exception ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:openrouter, :stream, :exception],
          %{duration: duration},
          Map.merge(metadata, %{
            error: Exception.message(exception)
          })
        )

        {:error, Error.from_exception(exception)}
    end
  end

  # Private helpers

  defp process_stream_chunk({response, start_time, metadata, chunk_count}) do
    receive do
      {^response, {:data, data}} ->
        # Parse SSE data
        case parse_sse_event(data) do
          {:ok, event} ->
            # Emit chunk event
            :telemetry.execute(
              [:openrouter, :stream, :chunk],
              %{chunk_size: byte_size(data)},
              metadata
            )

            {[event], {response, start_time, metadata, chunk_count + 1}}

          :done ->
            {:halt, {response, start_time, metadata, chunk_count}}

          :skip ->
            {[], {response, start_time, metadata, chunk_count}}
        end

      {^response, :done} ->
        {:halt, {response, start_time, metadata, chunk_count}}

      {^response, {:error, error}} ->
        raise error
    after
      60_000 ->
        {:halt, {response, start_time, metadata, chunk_count}}
    end
  end

  defp parse_sse_event(data) do
    # SSE format: "data: {...}\n\n"
    data
    |> String.trim()
    |> String.split("\n")
    |> Enum.find_value(:skip, fn line ->
      case String.trim(line) do
        "data: [DONE]" ->
          :done

        "data: " <> json_data ->
          case Jason.decode(json_data) do
            {:ok, decoded} -> {:ok, decoded}
            {:error, _} -> :skip
          end

        _ ->
          nil
      end
    end)
  end
end
