defmodule Openrouter.RetryTest do
  use ExUnit.Case, async: true

  alias Openrouter.Retry
  alias Openrouter.Types.Error

  describe "exponential_backoff/4" do
    test "calculates exponential backoff without jitter" do
      assert Retry.exponential_backoff(1, 1000, 32_000, false) == 1000
      assert Retry.exponential_backoff(2, 1000, 32_000, false) == 2000
      assert Retry.exponential_backoff(3, 1000, 32_000, false) == 4000
      assert Retry.exponential_backoff(4, 1000, 32_000, false) == 8000
      assert Retry.exponential_backoff(5, 1000, 32_000, false) == 16_000
      assert Retry.exponential_backoff(6, 1000, 32_000, false) == 32_000
      # Should cap at max_delay
      assert Retry.exponential_backoff(7, 1000, 32_000, false) == 32_000
    end

    test "adds jitter when enabled" do
      # With jitter, the delay should be base_delay + random jitter
      delay = Retry.exponential_backoff(1, 1000, 32_000, true)
      assert delay >= 1000
      # Max 25% jitter
      assert delay <= 1250
    end
  end

  describe "retryable?/2" do
    test "returns true for retryable errors" do
      error = Error.new(:rate_limit, "Rate limited")
      assert Retry.retryable?(error)

      error = Error.new(:server_error, "Server error")
      assert Retry.retryable?(error)

      error = Error.new(:timeout, "Timeout")
      assert Retry.retryable?(error)

      error = Error.new(:network_error, "Network error")
      assert Retry.retryable?(error)
    end

    test "returns false for non-retryable errors" do
      error = Error.new(:authentication, "Invalid API key")
      refute Retry.retryable?(error)

      error = Error.new(:invalid_request, "Bad request")
      refute Retry.retryable?(error)

      error = Error.new(:permission_denied, "No permission")
      refute Retry.retryable?(error)
    end

    test "respects custom retry_on list" do
      error = Error.new(:rate_limit, "Rate limited")
      assert Retry.retryable?(error, [:rate_limit])
      refute Retry.retryable?(error, [:server_error])
    end
  end

  describe "with_retry/2" do
    test "succeeds on first attempt" do
      call_count = :counters.new(1, [])

      result =
        Retry.with_retry(fn ->
          :counters.add(call_count, 1, 1)
          {:ok, "success"}
        end)

      assert result == {:ok, "success"}
      assert :counters.get(call_count, 1) == 1
    end

    test "retries on retryable errors" do
      call_count = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            count = :counters.get(call_count, 1)

            if count < 3 do
              {:error, Error.new(:rate_limit, "Rate limited")}
            else
              {:ok, "success"}
            end
          end,
          max_attempts: 3,
          base_delay: 10
        )

      assert result == {:ok, "success"}
      assert :counters.get(call_count, 1) == 3
    end

    test "stops retrying after max attempts" do
      call_count = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.new(:rate_limit, "Rate limited")}
          end,
          max_attempts: 3,
          base_delay: 10
        )

      # Returns the original error after exhausting retries
      assert {:error, %Error{type: :rate_limit}} = result
      assert :counters.get(call_count, 1) == 3
    end

    test "does not retry non-retryable errors" do
      call_count = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.new(:authentication, "Invalid key")}
          end,
          max_attempts: 3,
          base_delay: 10
        )

      assert {:error, %Error{type: :authentication}} = result
      assert :counters.get(call_count, 1) == 1
    end

    test "respects retry_after from error" do
      start_time = System.monotonic_time(:millisecond)

      Retry.with_retry(
        fn ->
          {:error, Error.new(:rate_limit, "Rate limited", retry_after: 0.1)}
        end,
        max_attempts: 2,
        base_delay: 10
      )

      elapsed = System.monotonic_time(:millisecond) - start_time
      # Should wait at least retry_after (100ms)
      assert elapsed >= 100
    end

    test "uses custom retry_on list" do
      call_count = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.new(:server_error, "Server error")}
          end,
          max_attempts: 3,
          base_delay: 10,
          # Only retry rate_limit errors
          retry_on: [:rate_limit]
        )

      # Should not retry since server_error is not in retry_on list
      assert {:error, %Error{type: :server_error}} = result
      assert :counters.get(call_count, 1) == 1
    end
  end
end
