defmodule Openrouter.Telemetry do
  @moduledoc """
  Telemetry integration for observability and monitoring.

  This module provides utilities for working with telemetry events emitted
  by the library. All events follow the `:telemetry` standard.

  ## Events

  The library emits the following telemetry events:

  ### Request Events

  #### `[:openrouter, :request, :start]`

  Emitted when an HTTP request starts.

  Measurements:
  - `:system_time` - System time when the request started

  Metadata:
  - `:method` - HTTP method (:get, :post, etc.)
  - `:url` - Request URL
  - `:model` - Model being used (if available)

  #### `[:openrouter, :request, :stop]`

  Emitted when an HTTP request completes successfully.

  Measurements:
  - `:duration` - Request duration in native time units

  Metadata:
  - `:method` - HTTP method
  - `:url` - Request URL
  - `:model` - Model used
  - `:status` - :ok
  - `:tokens` - Token usage map (prompt_tokens, completion_tokens, total_tokens)

  #### `[:openrouter, :request, :exception]`

  Emitted when an HTTP request fails.

  Measurements:
  - `:duration` - Request duration in native time units

  Metadata:
  - `:method` - HTTP method
  - `:url` - Request URL
  - `:model` - Model (if available)
  - `:error_type` - Error type atom
  - `:error_message` - Error message
  - `:status_code` - HTTP status code (if available)

  ### Streaming Events

  #### `[:openrouter, :stream, :start]`

  Emitted when a streaming request starts.

  Measurements:
  - `:system_time` - System time when streaming started

  Metadata:
  - `:method` - HTTP method
  - `:url` - Request URL
  - `:model` - Model being used (if available)
  - `:streaming` - true

  #### `[:openrouter, :stream, :chunk]`

  Emitted for each chunk received during streaming.

  Measurements:
  - `:chunk_size` - Size of the chunk in bytes

  Metadata:
  - `:method` - HTTP method
  - `:url` - Request URL
  - `:model` - Model being used
  - `:streaming` - true

  #### `[:openrouter, :stream, :stop]`

  Emitted when streaming completes.

  Measurements:
  - `:duration` - Total streaming duration in native time units
  - `:chunk_count` - Total number of chunks received

  Metadata:
  - `:method` - HTTP method
  - `:url` - Request URL
  - `:model` - Model being used
  - `:streaming` - true

  #### `[:openrouter, :stream, :exception]`

  Emitted when streaming fails.

  Measurements:
  - `:duration` - Duration before failure in native time units

  Metadata:
  - `:method` - HTTP method
  - `:url` - Request URL
  - `:model` - Model (if available)
  - `:streaming` - true
  - `:error` - Error message

  ## Usage

  ### Attaching Handlers

      # In your application.ex
      def start(_type, _args) do
        Openrouter.Telemetry.attach_default_handler()

        # ... rest of your supervision tree
      end

  ### Custom Handlers

      :telemetry.attach_many(
        "my-app-openrouter-handler",
        [
          [:openrouter, :request, :start],
          [:openrouter, :request, :stop],
          [:openrouter, :request, :exception]
        ],
        &MyApp.TelemetryHandler.handle_event/4,
        nil
      )

      defmodule MyApp.TelemetryHandler do
        require Logger

        def handle_event([:openrouter, :request, :start], _measurements, _metadata, _config) do
          Logger.debug("Starting request")
        end

        def handle_event([:openrouter, :request, :stop], measurements, metadata, _config) do
          duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
          tokens = metadata.tokens["total_tokens"]

          Logger.info("Request completed",
            duration_ms: duration_ms,
            model: metadata.model,
            tokens: tokens
          )
        end

        def handle_event([:openrouter, :request, :exception], measurements, metadata, _config) do
          duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

          Logger.error("Request failed",
            duration_ms: duration_ms,
            error: metadata.error_type,
            message: metadata.error_message
          )
        end
      end

  ### Metrics with Telemetry.Metrics

      # In your application
      def metrics do
        [
          # Request count
          counter("openrouter.request.count",
            event_name: [:openrouter, :request, :stop],
            description: "Total number of requests"
          ),

          # Request duration
          distribution("openrouter.request.duration",
            event_name: [:openrouter, :request, :stop],
            measurement: :duration,
            unit: {:native, :millisecond},
            description: "Request duration"
          ),

          # Token usage
          sum("openrouter.tokens.total",
            event_name: [:openrouter, :request, :stop],
            measurement: fn metadata ->
              get_in(metadata, [:tokens, "total_tokens"]) || 0
            end,
            description: "Total tokens used"
          ),

          # Error count
          counter("openrouter.request.errors",
            event_name: [:openrouter, :request, :exception],
            description: "Total number of errors"
          )
        ]
      end
  """

  require Logger

  @doc """
  Attaches a default telemetry handler that logs events.

  This is useful for development and debugging.

  ## Options

    * `:level` - Log level (:debug, :info, :warning, :error) (default: :info)

  ## Examples

      Openrouter.Telemetry.attach_default_handler()
      Openrouter.Telemetry.attach_default_handler(level: :debug)
  """
  @spec attach_default_handler(keyword()) :: :ok | {:error, :already_exists}
  def attach_default_handler(opts \\ []) do
    level = Keyword.get(opts, :level, :info)

    :telemetry.attach_many(
      "openrouter-default-handler",
      [
        [:openrouter, :request, :start],
        [:openrouter, :request, :stop],
        [:openrouter, :request, :exception],
        [:openrouter, :stream, :start],
        [:openrouter, :stream, :stop],
        [:openrouter, :stream, :exception]
      ],
      &__MODULE__.handle_event/4,
      %{level: level}
    )
  end

  @doc """
  Detaches the default telemetry handler.
  """
  @spec detach_default_handler() :: :ok | {:error, :not_found}
  def detach_default_handler do
    :telemetry.detach("openrouter-default-handler")
  end

  @doc false
  def handle_event([:openrouter, :request, :start], _measurements, metadata, config) do
    log(config.level, "Request started", model: metadata.model)
  end

  def handle_event([:openrouter, :request, :stop], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    tokens = get_in(metadata, [:tokens, "total_tokens"]) || 0

    log(
      config.level,
      "Request completed",
      duration_ms: duration_ms,
      model: metadata.model,
      tokens: tokens
    )
  end

  def handle_event([:openrouter, :request, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    log(
      :error,
      "Request failed",
      duration_ms: duration_ms,
      error: metadata.error_type,
      message: metadata.error_message
    )
  end

  def handle_event([:openrouter, :stream, :start], _measurements, metadata, config) do
    log(config.level, "Stream started", model: metadata.model)
  end

  def handle_event([:openrouter, :stream, :stop], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    log(
      config.level,
      "Stream completed",
      duration_ms: duration_ms,
      chunks: measurements.chunk_count,
      model: metadata.model
    )
  end

  def handle_event([:openrouter, :stream, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    log(
      :error,
      "Stream failed",
      duration_ms: duration_ms,
      error: metadata.error
    )
  end

  # Private helpers

  defp log(level, message, metadata) do
    Logger.log(level, message, metadata)
  end
end
