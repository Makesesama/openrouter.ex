defmodule Openrouter.Retry do
  @moduledoc """
  Retry logic with exponential backoff for production resilience.

  This module provides retry functionality with:
  - Exponential backoff with jitter
  - Configurable max attempts
  - Error type filtering (retry only on specific errors)
  - Timeout handling

  ## Examples

      # Simple retry
      Openrouter.Retry.with_retry(fn ->
        Openrouter.chat("Hello", model: "gpt-4")
      end)

      # With custom options
      Openrouter.Retry.with_retry(
        fn -> make_api_call() end,
        max_attempts: 5,
        base_delay: 2000,
        max_delay: 30000
      )

      # Retry only on specific errors
      Openrouter.Retry.with_retry(
        fn -> make_api_call() end,
        retry_on: [:rate_limit, :server_error, :timeout]
      )
  """

  alias Openrouter.Types.Error

  require Logger

  @type retry_opts :: [
          max_attempts: pos_integer(),
          base_delay: pos_integer(),
          max_delay: pos_integer(),
          retry_on: [Error.error_type()],
          jitter: boolean()
        ]

  @default_max_attempts 3
  @default_base_delay 1000
  @default_max_delay 32_000

  @doc """
  Executes a function with automatic retry on failures.

  ## Options

    * `:max_attempts` - Maximum number of attempts (default: 3)
    * `:base_delay` - Base delay in milliseconds (default: 1000)
    * `:max_delay` - Maximum delay in milliseconds (default: 32000)
    * `:retry_on` - List of error types to retry on (default: all retryable errors)
    * `:jitter` - Add random jitter to delays (default: true)

  ## Examples

      # Retry with defaults
      {:ok, result} = Openrouter.Retry.with_retry(fn ->
        Openrouter.chat("Hello", model: "gpt-4")
      end)

      # Custom retry configuration
      {:ok, result} = Openrouter.Retry.with_retry(
        fn -> make_request() end,
        max_attempts: 5,
        base_delay: 2000,
        retry_on: [:rate_limit, :server_error]
      )
  """
  @spec with_retry((-> {:ok, any()} | {:error, Error.t()}), retry_opts()) ::
          {:ok, any()} | {:error, Error.t()}
  def with_retry(fun, opts \\ []) when is_function(fun, 0) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    base_delay = Keyword.get(opts, :base_delay, @default_base_delay)
    max_delay = Keyword.get(opts, :max_delay, @default_max_delay)
    retry_on = Keyword.get(opts, :retry_on, default_retryable_errors())
    jitter = Keyword.get(opts, :jitter, true)

    do_retry(fun, max_attempts, base_delay, max_delay, retry_on, jitter, 1)
  end

  @doc """
  Calculates the delay for exponential backoff.

  ## Examples

      iex> Openrouter.Retry.exponential_backoff(1, 1000, 32000, false)
      1000

      iex> Openrouter.Retry.exponential_backoff(2, 1000, 32000, false)
      2000

      iex> Openrouter.Retry.exponential_backoff(3, 1000, 32000, false)
      4000
  """
  @spec exponential_backoff(pos_integer(), pos_integer(), pos_integer(), boolean()) ::
          pos_integer()
  def exponential_backoff(attempt, base_delay, max_delay, jitter \\ true) do
    # Calculate exponential delay: base_delay * 2^(attempt - 1)
    delay = min(base_delay * :math.pow(2, attempt - 1), max_delay) |> trunc()

    if jitter do
      # Add random jitter between 0% and 25% of the delay
      jitter_amount = trunc(delay * :rand.uniform() * 0.25)
      delay + jitter_amount
    else
      delay
    end
  end

  @doc """
  Checks if an error is retryable.

  ## Examples

      iex> error = Openrouter.Types.Error.new(:rate_limit, "Rate limited")
      iex> Openrouter.Retry.retryable?(error)
      true

      iex> error = Openrouter.Types.Error.new(:authentication, "Invalid API key")
      iex> Openrouter.Retry.retryable?(error)
      false
  """
  @spec retryable?(Error.t(), [Error.error_type()]) :: boolean()
  def retryable?(%Error{type: type}, retry_on \\ default_retryable_errors()) do
    type in retry_on
  end

  # Private functions

  defp do_retry(_fun, max_attempts, _base_delay, _max_delay, _retry_on, _jitter, attempt)
       when attempt > max_attempts do
    {:error, Error.new(:timeout, "Maximum retry attempts (#{max_attempts}) exceeded")}
  end

  defp do_retry(fun, max_attempts, base_delay, max_delay, retry_on, jitter, attempt) do
    case fun.() do
      {:ok, _result} = success ->
        success

      {:error, %Error{} = error} = failure ->
        should_retry = retryable?(error, retry_on) and attempt < max_attempts

        case should_retry do
          true ->
            # Calculate delay
            delay = exponential_backoff(attempt, base_delay, max_delay, jitter)

            # Log retry attempt
            Logger.warning(
              "Request failed with #{error.type}, retrying in #{delay}ms (attempt #{attempt}/#{max_attempts})"
            )

            # Wait before retry (respect retry_after if provided)
            actual_delay = calculate_actual_delay(error, delay)
            Process.sleep(actual_delay)

            # Retry
            do_retry(fun, max_attempts, base_delay, max_delay, retry_on, jitter, attempt + 1)

          false ->
            # Error is not retryable or max attempts reached
            log_final_error(attempt, max_attempts, error)
            failure
        end

      other ->
        # Unexpected return value
        other
    end
  end

  defp calculate_actual_delay(error, delay) do
    case error.retry_after do
      nil -> delay
      retry_after -> trunc(retry_after * 1000)
    end
  end

  defp log_final_error(attempt, max_attempts, error) do
    if attempt >= max_attempts do
      Logger.error("Request failed after #{max_attempts} attempts: #{error.message}")
    end
  end

  defp default_retryable_errors do
    [
      :rate_limit,
      :server_error,
      :timeout,
      :network_error
    ]
  end
end
