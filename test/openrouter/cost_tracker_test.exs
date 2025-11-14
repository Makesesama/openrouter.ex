defmodule Openrouter.CostTrackerTest do
  use ExUnit.Case, async: true

  alias Openrouter.CostTracker
  alias Openrouter.Types.{Response, Usage}

  describe "start_link/1" do
    test "starts without budget" do
      assert {:ok, pid} = CostTracker.start_link()
      assert Process.alive?(pid)
    end

    test "starts with budget" do
      assert {:ok, pid} = CostTracker.start_link(budget: 10.00)
      assert Process.alive?(pid)
    end

    test "starts with custom warning threshold" do
      assert {:ok, pid} = CostTracker.start_link(
        budget: 10.00,
        budget_warning_threshold: 0.9
      )
      assert Process.alive?(pid)
    end

    test "can be named" do
      assert {:ok, pid} = CostTracker.start_link(name: __MODULE__.TestTracker)
      assert Process.whereis(__MODULE__.TestTracker) == pid
    end
  end

  describe "track/3" do
    test "tracks a response with usage data" do
      {:ok, tracker} = CostTracker.start_link()

      response = build_response(
        model: "openai/gpt-3.5-turbo",
        usage: %{
          prompt_tokens: 10,
          completion_tokens: 20,
          total_tokens: 30,
          total_cost: 0.001
        }
      )

      assert :ok = CostTracker.track(tracker, response)

      usage = CostTracker.get_usage(tracker)
      assert usage.total_cost == 0.001
      assert usage.total_tokens == 30
      assert usage.request_count == 1
    end

    test "returns error when response has no usage data" do
      {:ok, tracker} = CostTracker.start_link()

      response = build_response(model: "openai/gpt-3.5-turbo", usage: nil)

      assert {:error, :no_usage_data} = CostTracker.track(tracker, response)
    end

    test "tracks multiple responses" do
      {:ok, tracker} = CostTracker.start_link()

      response1 = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 100, total_cost: 0.01}
      )

      response2 = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 200, total_cost: 0.02}
      )

      :ok = CostTracker.track(tracker, response1)
      :ok = CostTracker.track(tracker, response2)

      usage = CostTracker.get_usage(tracker)
      assert usage.total_cost == 0.03
      assert usage.total_tokens == 300
      assert usage.request_count == 2
      assert_in_delta usage.average_cost_per_request, 0.015, 0.001
    end

    test "tracks per-model statistics" do
      {:ok, tracker} = CostTracker.start_link()

      gpt4_response = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 100, total_cost: 0.05}
      )

      gpt35_response = build_response(
        model: "openai/gpt-3.5-turbo",
        usage: %{total_tokens: 150, total_cost: 0.01}
      )

      :ok = CostTracker.track(tracker, gpt4_response)
      :ok = CostTracker.track(tracker, gpt35_response)

      stats = CostTracker.get_stats(tracker)

      assert stats.by_model["openai/gpt-4"].cost == 0.05
      assert stats.by_model["openai/gpt-4"].tokens == 100
      assert stats.by_model["openai/gpt-4"].requests == 1

      assert stats.by_model["openai/gpt-3.5-turbo"].cost == 0.01
      assert stats.by_model["openai/gpt-3.5-turbo"].tokens == 150
      assert stats.by_model["openai/gpt-3.5-turbo"].requests == 1
    end

    test "tracks per-session statistics" do
      {:ok, tracker} = CostTracker.start_link()

      response1 = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 100, total_cost: 0.01}
      )

      response2 = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 150, total_cost: 0.015}
      )

      :ok = CostTracker.track(tracker, response1, session_id: "session-1")
      :ok = CostTracker.track(tracker, response2, session_id: "session-1")

      session_stats = CostTracker.get_session_stats(tracker, "session-1")
      assert session_stats.cost == 0.025
      assert session_stats.tokens == 250
      assert session_stats.requests == 2
    end

    test "tracks multiple sessions separately" do
      {:ok, tracker} = CostTracker.start_link()

      r1 = build_response(model: "openai/gpt-4", usage: %{total_tokens: 100, total_cost: 0.01})
      r2 = build_response(model: "openai/gpt-4", usage: %{total_tokens: 200, total_cost: 0.02})

      :ok = CostTracker.track(tracker, r1, session_id: "session-1")
      :ok = CostTracker.track(tracker, r2, session_id: "session-2")

      stats1 = CostTracker.get_session_stats(tracker, "session-1")
      stats2 = CostTracker.get_session_stats(tracker, "session-2")

      assert stats1.cost == 0.01
      assert stats2.cost == 0.02
    end
  end

  describe "track_usage/4" do
    test "tracks usage directly" do
      {:ok, tracker} = CostTracker.start_link()

      usage = %Usage{
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30,
        total_cost: 0.001
      }

      assert :ok = CostTracker.track_usage(tracker, usage, "openai/gpt-4")

      stats = CostTracker.get_usage(tracker)
      assert stats.total_cost == 0.001
      assert stats.total_tokens == 30
    end
  end

  describe "check_budget/1" do
    test "returns :ok when no budget set" do
      {:ok, tracker} = CostTracker.start_link()

      response = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 100, total_cost: 100.00}
      )

      :ok = CostTracker.track(tracker, response)

      assert :ok = CostTracker.check_budget(tracker)
    end

    test "returns :ok when within budget" do
      {:ok, tracker} = CostTracker.start_link(budget: 10.00)

      response = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 100, total_cost: 1.00}
      )

      :ok = CostTracker.track(tracker, response)

      assert :ok = CostTracker.check_budget(tracker)
    end

    test "returns {:warning, remaining} when approaching budget" do
      {:ok, tracker} = CostTracker.start_link(budget: 10.00, budget_warning_threshold: 0.8)

      response = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 100, total_cost: 8.50}
      )

      :ok = CostTracker.track(tracker, response)

      assert {:warning, remaining} = CostTracker.check_budget(tracker)
      assert_in_delta remaining, 1.50, 0.01
    end

    test "returns {:exceeded, amount} when budget exceeded" do
      {:ok, tracker} = CostTracker.start_link(budget: 10.00)

      response = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 100, total_cost: 12.00}
      )

      :ok = CostTracker.track(tracker, response)

      assert {:exceeded, amount} = CostTracker.check_budget(tracker)
      assert_in_delta amount, 2.00, 0.01
    end
  end

  describe "reset/1" do
    test "resets all tracking data" do
      {:ok, tracker} = CostTracker.start_link(budget: 10.00)

      response = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 100, total_cost: 5.00}
      )

      :ok = CostTracker.track(tracker, response)

      usage = CostTracker.get_usage(tracker)
      assert usage.total_cost == 5.00

      :ok = CostTracker.reset(tracker)

      usage = CostTracker.get_usage(tracker)
      assert usage.total_cost == 0.0
      assert usage.total_tokens == 0
      assert usage.request_count == 0
    end

    test "preserves budget after reset" do
      {:ok, tracker} = CostTracker.start_link(budget: 10.00)
      :ok = CostTracker.reset(tracker)

      stats = CostTracker.get_stats(tracker)
      assert stats.budget == 10.00
    end
  end

  describe "set_budget/2" do
    test "updates budget" do
      {:ok, tracker} = CostTracker.start_link(budget: 10.00)
      :ok = CostTracker.set_budget(tracker, 20.00)

      stats = CostTracker.get_stats(tracker)
      assert stats.budget == 20.00
    end

    test "can set budget to nil" do
      {:ok, tracker} = CostTracker.start_link(budget: 10.00)
      :ok = CostTracker.set_budget(tracker, nil)

      stats = CostTracker.get_stats(tracker)
      assert stats.budget == nil
    end
  end

  describe "get_stats/1" do
    test "returns comprehensive statistics" do
      {:ok, tracker} = CostTracker.start_link(budget: 10.00)

      response = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 100, total_cost: 0.50}
      )

      :ok = CostTracker.track(tracker, response, session_id: "session-1")

      stats = CostTracker.get_stats(tracker)

      assert stats.total_cost == 0.50
      assert stats.total_tokens == 100
      assert stats.request_count == 1
      assert stats.average_cost_per_request == 0.50
      assert is_map(stats.by_model)
      assert is_map(stats.by_session)
      assert stats.budget == 10.00
      assert stats.budget_status == :ok
      assert %DateTime{} = stats.started_at
      assert is_integer(stats.duration)
    end
  end

  describe "format_report/1" do
    test "generates human-readable report" do
      {:ok, tracker} = CostTracker.start_link(budget: 10.00)

      response = build_response(
        model: "openai/gpt-4",
        usage: %{total_tokens: 100, total_cost: 0.50}
      )

      :ok = CostTracker.track(tracker, response)

      report = CostTracker.format_report(tracker)

      assert report =~ "Cost Tracker Report"
      assert report =~ "Total Cost:"
      assert report =~ "Total Tokens:"
      assert report =~ "By Model:"
      assert report =~ "openai/gpt-4"
    end
  end

  # Helper functions

  defp build_response(opts) do
    model = Keyword.get(opts, :model, "openai/gpt-3.5-turbo")
    usage_data = Keyword.get(opts, :usage)

    usage =
      if usage_data do
        %Usage{
          prompt_tokens: Map.get(usage_data, :prompt_tokens, 0),
          completion_tokens: Map.get(usage_data, :completion_tokens, 0),
          total_tokens: Map.get(usage_data, :total_tokens, 0),
          total_cost: Map.get(usage_data, :total_cost)
        }
      else
        nil
      end

    %Response{
      id: "test-#{:rand.uniform(10000)}",
      model: model,
      content: "Test response",
      role: :assistant,
      usage: usage
    }
  end
end
