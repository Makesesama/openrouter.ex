defmodule Openrouter.Provider.OpenRouter do
  @moduledoc """
  OpenRouter provider implementation.

  Handles all communication with the OpenRouter API.
  """

  @behaviour Openrouter.Provider

  alias Openrouter.HTTP
  alias Openrouter.Types.{Error, Message, Response}

  @impl true
  def name, do: "openrouter"

  @impl true
  def request(config, messages, params) do
    url = build_url(config, "/chat/completions")
    headers = build_headers(config)
    body = build_request_body(messages, params)

    case HTTP.request(url: url, headers: headers, json: body, timeout: params[:timeout]) do
      {:ok, response_data} ->
        {:ok, Response.from_api_format(response_data)}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def request_stream(config, messages, params) do
    url = build_url(config, "/chat/completions")
    headers = build_headers(config)
    body = build_request_body(messages, params)

    case HTTP.request_stream(url: url, headers: headers, json: body, timeout: params[:timeout]) do
      {:ok, stream} ->
        {:ok, transform_stream(stream)}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def embeddings(config, texts, params) do
    url = build_url(config, "/embeddings")
    headers = build_headers(config)

    body = %{
      input: texts,
      model: params[:model] || config[:default_model] || "text-embedding-3-small"
    }

    case HTTP.request(url: url, headers: headers, json: body, timeout: params[:timeout]) do
      {:ok, %{"data" => data}} ->
        embeddings = Enum.map(data, fn item -> item["embedding"] end)
        {:ok, embeddings}

      {:ok, %{"error" => error_data}} ->
        # API returned an error in successful response
        status_code = error_data["code"] || 500
        message = error_data["message"] || "Unknown error"
        type = error_code_to_type(status_code)

        {:error, Error.new(type, message, status_code: status_code)}

      {:error, _} = error ->
        error
    end
  end

  # Private helpers

  defp build_url(config, path) do
    base_url = config[:base_url] || "https://openrouter.ai/api/v1"
    base_url <> path
  end

  defp build_headers(config) do
    api_key = config[:api_key]

    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{api_key}"}
    ]

    headers =
      if app_name = config[:app_name] do
        [{"http-referer", app_name} | headers]
      else
        headers
      end

    if site_url = config[:site_url] do
      [{"x-title", site_url} | headers]
    else
      headers
    end
  end

  defp build_request_body(messages, params) do
    # Convert messages to API format
    api_messages =
      Enum.map(messages, fn msg ->
        Message.to_api_format(msg)
      end)

    %{
      messages: api_messages,
      model: params[:model]
    }
    |> maybe_add(:temperature, params[:temperature])
    |> maybe_add(:max_tokens, params[:max_tokens])
    |> maybe_add(:top_p, params[:top_p])
    |> maybe_add(:frequency_penalty, params[:frequency_penalty])
    |> maybe_add(:presence_penalty, params[:presence_penalty])
    |> maybe_add(:stop, params[:stop])
    |> maybe_add(:tools, params[:tools])
    |> maybe_add(:tool_choice, params[:tool_choice])
    |> maybe_add(:response_format, params[:response_format])
  end

  defp transform_stream(stream) do
    stream
    |> Stream.map(fn chunk ->
      parse_stream_chunk(chunk)
    end)
    |> Stream.reject(&is_nil/1)
  end

  defp parse_stream_chunk(chunk) do
    # Extract the delta from the chunk
    choice = get_in(chunk, ["choices", Access.at(0)])

    if choice do
      delta = choice["delta"]
      finish_reason = choice["finish_reason"]

      cond do
        # Check finish_reason first, as it signals stream completion
        finish_reason ->
          %{type: :done, finish_reason: finish_reason}

        delta && delta["content"] && delta["content"] != "" ->
          %{type: :content, content: delta["content"]}

        delta && delta["tool_calls"] ->
          %{type: :tool_calls, tool_calls: delta["tool_calls"]}

        true ->
          nil
      end
    else
      nil
    end
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp error_code_to_type(code) when code in 400..499, do: :invalid_request
  defp error_code_to_type(code) when code in 500..599, do: :server_error
  defp error_code_to_type(_code), do: :unknown_error
end
