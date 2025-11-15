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

    # Add Req.Test plug for test environment (required for reqord)
    request_opts =
      if Application.get_env(:openrouter, :req_options) do
        Keyword.merge(Application.get_env(:openrouter, :req_options), request_opts)
      else
        request_opts
      end

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

    # Add Req.Test plug for test environment (required for reqord)
    request_opts =
      if Application.get_env(:openrouter, :req_options) do
        Keyword.merge(Application.get_env(:openrouter, :req_options), request_opts)
      else
        request_opts
      end

    try do
      response = Req.request!(request_opts)

      # Check what type of body we got
      stream =
        case response.body do
          %Req.Response.Async{ref: ref} ->
            # Live streaming - extract ref and process messages
            Stream.resource(
              fn -> {ref, start_time, metadata, 0} end,
              &process_stream_chunk/1,
              fn {_ref, start_time, metadata, chunk_count} ->
                duration = System.monotonic_time() - start_time

                :telemetry.execute(
                  [:openrouter, :stream, :stop],
                  %{duration: duration, chunk_count: chunk_count},
                  metadata
                )
              end
            )

          body when is_binary(body) ->
            # Cassette replay - body is already the full SSE response
            # Parse the SSE data directly
            Stream.resource(
              fn -> {body, start_time, metadata, 0} end,
              &process_cassette_stream/1,
              fn {_body, start_time, metadata, chunk_count} ->
                duration = System.monotonic_time() - start_time

                :telemetry.execute(
                  [:openrouter, :stream, :stop],
                  %{duration: duration, chunk_count: chunk_count},
                  metadata
                )
              end
            )

          other ->
            raise "Unexpected response body type: #{inspect(other)}"
        end

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

  defp process_cassette_stream({"", _start_time, _metadata, chunk_count}) do
    # No more data to process
    {:halt, {"", 0, %{}, chunk_count}}
  end

  defp process_cassette_stream({body, start_time, metadata, chunk_count}) do
    # Split the body into SSE events (separated by \n\n)
    case String.split(body, "\n\n", parts: 2) do
      [event_data, rest] when event_data != "" ->
        # Parse this SSE event
        case parse_sse_event(event_data) do
          {:ok, event} ->
            # Emit telemetry
            :telemetry.execute(
              [:openrouter, :stream, :chunk],
              %{chunk_size: byte_size(event_data)},
              metadata
            )

            {[event], {rest, start_time, metadata, chunk_count + 1}}

          :done ->
            {:halt, {rest, start_time, metadata, chunk_count}}

          :skip ->
            # Skip this chunk and continue with rest
            {[], {rest, start_time, metadata, chunk_count}}
        end

      _ ->
        # No complete event found, we're done
        {:halt, {body, start_time, metadata, chunk_count}}
    end
  end

  defp process_stream_chunk({ref, start_time, metadata, chunk_count}) do
    receive do
      {^ref, {:data, data}} ->
        # Parse SSE data - may contain multiple events separated by \n\n
        events = parse_sse_events(data)

        :telemetry.execute(
          [:openrouter, :stream, :chunk],
          %{chunk_size: byte_size(data)},
          metadata
        )

        # Filter out :skip and :done markers, extract actual events
        actual_events =
          Enum.filter(events, fn
            {:ok, _event} -> true
            _ -> false
          end)
          |> Enum.map(fn {:ok, event} -> event end)

        # Check if we got a :done marker
        has_done = Enum.any?(events, &(&1 == :done))

        cond do
          has_done ->
            # Stream is complete
            {actual_events, {ref, start_time, metadata, chunk_count + length(actual_events)}}
            |> then(fn result ->
              # Return events then halt
              result
            end)

          # Actually we need to halt after returning these events
          # But Stream.resource doesn't allow that, so we'll check in next iteration

          length(actual_events) > 0 ->
            {actual_events, {ref, start_time, metadata, chunk_count + length(actual_events)}}

          true ->
            # No valid events, continue
            {[], {ref, start_time, metadata, chunk_count}}
        end

      {^ref, :done} ->
        {:halt, {ref, start_time, metadata, chunk_count}}

      {^ref, {:error, error}} ->
        raise error
    after
      60_000 ->
        {:halt, {ref, start_time, metadata, chunk_count}}
    end
  end

  defp parse_sse_events(data) do
    # SSE events are separated by \n\n
    # Split into individual events and parse each one
    data
    |> String.split("\n\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_sse_event/1)
  end

  defp parse_sse_event(data) do
    # SSE format: "data: {...}\n\n"  or just "data: {...}"
    data
    |> String.trim()
    |> String.split("\n")
    |> Enum.find_value(:skip, &parse_sse_line/1)
  end

  defp parse_sse_line(line) do
    case String.trim(line) do
      "data: [DONE]" -> :done
      "data: " <> json_data -> decode_json_data(json_data)
      _ -> nil
    end
  end

  defp decode_json_data(json_data) do
    case Jason.decode(json_data) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> :skip
    end
  end
end
