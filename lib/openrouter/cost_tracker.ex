defmodule Openrouter.CostTracker do
  @moduledoc """
  Cost tracking and budgeting utilities for OpenRouter API usage.

  CostTracker helps you monitor and control AI spending by tracking costs
  across multiple requests, setting budgets, and providing usage reports.

  ## Features

  - Track costs across multiple requests
  - Set budgets and get alerts when exceeded
  - Per-model cost tracking
  - Session-based tracking
  - Usage reports and analytics

  ## Usage

  ### Basic Tracking

      {:ok, tracker} = CostTracker.start_link()

      # Track a request
      {:ok, response} = Openrouter.chat("Hello", usage: %{include: true})
      :ok = CostTracker.track(tracker, response)

      # Get current usage
      usage = CostTracker.get_usage(tracker)
      IO.puts("Total cost: $\#{usage.total_cost}")

  ### With Budget Limits

      {:ok, tracker} = CostTracker.start_link(budget: 10.00)

      case CostTracker.check_budget(tracker) do
        :ok ->
          # Make API call
        {:exceeded, amount} ->
          Logger.warn("Budget exceeded by $\#{amount}")
      end

  ### Per-Model Tracking

      {:ok, response} = Openrouter.chat("Hello", model: "openai/gpt-4")
      :ok = CostTracker.track(tracker, response)

      # Get stats by model
      stats = CostTracker.get_stats(tracker)
      IO.inspect(stats.by_model)

  ### Session Tracking

      # Track costs for a specific session/conversation
      :ok = CostTracker.track(tracker, response, session_id: "conversation-123")

      # Get session stats
      session_stats = CostTracker.get_session_stats(tracker, "conversation-123")
  """

  use GenServer
  alias Openrouter.Types.{Response, Usage}
  require Logger

  @type tracker :: pid() | atom()
  @type budget_status :: :ok | {:exceeded, float()} | {:warning, float()}

  defstruct total_cost: 0.0,
            total_tokens: 0,
            request_count: 0,
            by_model: %{},
            by_session: %{},
            budget: nil,
            budget_warning_threshold: 0.8,
            started_at: nil,
            requests: []

  ## Client API

  @doc """
  Starts a new cost tracker process.

  ## Options

  - `:budget` - Maximum spend limit in USD (default: nil = unlimited)
  - `:budget_warning_threshold` - Warn when budget usage exceeds this ratio (default: 0.8 = 80%)
  - `:name` - Register the tracker with a name

  ## Examples

      {:ok, pid} = CostTracker.start_link()
      {:ok, pid} = CostTracker.start_link(budget: 50.00, name: MyApp.CostTracker)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, init_opts, name: name)
    else
      GenServer.start_link(__MODULE__, init_opts)
    end
  end

  @doc """
  Tracks a request and its associated cost.

  ## Options

  - `:session_id` - Associate this request with a session/conversation ID

  ## Examples

      {:ok, response} = Openrouter.chat("Hello", usage: %{include: true})
      :ok = CostTracker.track(tracker, response)

      # With session tracking
      :ok = CostTracker.track(tracker, response, session_id: "conv-123")
  """
  @spec track(tracker(), Response.t(), keyword()) :: :ok | {:error, term()}
  def track(tracker, %Response{} = response, opts \\ []) do
    GenServer.call(tracker, {:track, response, opts})
  end

  @doc """
  Tracks usage data directly.

  Useful when you have usage information but not a full response object.
  """
  @spec track_usage(tracker(), Usage.t(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def track_usage(tracker, %Usage{} = usage, model, opts \\ []) do
    GenServer.call(tracker, {:track_usage, usage, model, opts})
  end

  @doc """
  Gets the current total usage.

  Returns a map with:
  - `:total_cost` - Total USD spent
  - `:total_tokens` - Total tokens used
  - `:request_count` - Number of requests tracked
  - `:average_cost_per_request` - Average cost per request
  """
  @spec get_usage(tracker()) :: map()
  def get_usage(tracker) do
    GenServer.call(tracker, :get_usage)
  end

  @doc """
  Gets detailed statistics including per-model and per-session breakdowns.
  """
  @spec get_stats(tracker()) :: map()
  def get_stats(tracker) do
    GenServer.call(tracker, :get_stats)
  end

  @doc """
  Gets statistics for a specific session.
  """
  @spec get_session_stats(tracker(), String.t()) :: map() | nil
  def get_session_stats(tracker, session_id) do
    GenServer.call(tracker, {:get_session_stats, session_id})
  end

  @doc """
  Checks if the budget has been exceeded.

  Returns:
  - `:ok` - Within budget
  - `{:warning, remaining}` - Approaching budget limit
  - `{:exceeded, amount}` - Budget exceeded by amount
  """
  @spec check_budget(tracker()) :: budget_status()
  def check_budget(tracker) do
    GenServer.call(tracker, :check_budget)
  end

  @doc """
  Resets all tracking data.
  """
  @spec reset(tracker()) :: :ok
  def reset(tracker) do
    GenServer.call(tracker, :reset)
  end

  @doc """
  Updates the budget limit.
  """
  @spec set_budget(tracker(), float() | nil) :: :ok
  def set_budget(tracker, budget) do
    GenServer.call(tracker, {:set_budget, budget})
  end

  @doc """
  Generates a human-readable usage report.
  """
  @spec format_report(tracker()) :: String.t()
  def format_report(tracker) do
    stats = get_stats(tracker)

    """
    === Cost Tracker Report ===

    Total Cost: $#{Float.round(stats.total_cost, 6)}
    Total Tokens: #{stats.total_tokens}
    Total Requests: #{stats.request_count}
    Average Cost/Request: $#{Float.round(stats.average_cost_per_request, 6)}

    Duration: #{format_duration(stats.duration)}

    Budget Status: #{format_budget_status(stats.budget_status)}

    By Model:
    #{format_by_model(stats.by_model)}

    #{if map_size(stats.by_session) > 0, do: "By Session:\n#{format_by_session(stats.by_session)}", else: ""}
    """
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      budget: Keyword.get(opts, :budget),
      budget_warning_threshold: Keyword.get(opts, :budget_warning_threshold, 0.8),
      started_at: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:track, response, opts}, _from, state) do
    case response.usage do
      nil ->
        Logger.warning(
          "Response has no usage data. Enable cost tracking with: usage: %{include: true}"
        )

        {:reply, {:error, :no_usage_data}, state}

      usage ->
        new_state = do_track(state, usage, response.model, opts)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:track_usage, usage, model, opts}, _from, state) do
    new_state = do_track(state, usage, model, opts)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_usage, _from, state) do
    usage = %{
      total_cost: state.total_cost,
      total_tokens: state.total_tokens,
      request_count: state.request_count,
      average_cost_per_request:
        if(state.request_count > 0, do: state.total_cost / state.request_count, else: 0.0)
    }

    {:reply, usage, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_cost: state.total_cost,
      total_tokens: state.total_tokens,
      request_count: state.request_count,
      average_cost_per_request:
        if(state.request_count > 0, do: state.total_cost / state.request_count, else: 0.0),
      by_model: state.by_model,
      by_session: state.by_session,
      budget: state.budget,
      budget_status: calculate_budget_status(state),
      started_at: state.started_at,
      duration: DateTime.diff(DateTime.utc_now(), state.started_at)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_session_stats, session_id}, _from, state) do
    {:reply, Map.get(state.by_session, session_id), state}
  end

  @impl true
  def handle_call(:check_budget, _from, state) do
    status = calculate_budget_status(state)
    {:reply, status, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = %__MODULE__{
      budget: state.budget,
      budget_warning_threshold: state.budget_warning_threshold,
      started_at: DateTime.utc_now()
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_budget, budget}, _from, state) do
    {:reply, :ok, %{state | budget: budget}}
  end

  ## Private Helpers

  defp do_track(state, usage, model, opts) do
    cost = usage.total_cost || 0.0
    tokens = usage.total_tokens || 0
    session_id = Keyword.get(opts, :session_id)

    # Update totals
    state = %{
      state
      | total_cost: state.total_cost + cost,
        total_tokens: state.total_tokens + tokens,
        request_count: state.request_count + 1
    }

    # Update per-model stats
    model_stats = Map.get(state.by_model, model, %{cost: 0.0, tokens: 0, requests: 0})

    model_stats = %{
      cost: model_stats.cost + cost,
      tokens: model_stats.tokens + tokens,
      requests: model_stats.requests + 1
    }

    state = put_in(state.by_model[model], model_stats)

    # Update per-session stats if session_id provided
    state =
      if session_id do
        session_stats =
          Map.get(state.by_session, session_id, %{cost: 0.0, tokens: 0, requests: 0})

        session_stats = %{
          cost: session_stats.cost + cost,
          tokens: session_stats.tokens + tokens,
          requests: session_stats.requests + 1
        }

        put_in(state.by_session[session_id], session_stats)
      else
        state
      end

    # Check budget and log warning if needed
    check_and_warn_budget(state)

    state
  end

  defp calculate_budget_status(%{budget: nil}), do: :ok

  defp calculate_budget_status(state) do
    budget = state.budget
    spent = state.total_cost
    threshold = state.budget_warning_threshold

    cond do
      spent > budget ->
        {:exceeded, spent - budget}

      spent / budget >= threshold ->
        {:warning, budget - spent}

      true ->
        :ok
    end
  end

  defp check_and_warn_budget(state) do
    case calculate_budget_status(state) do
      {:exceeded, amount} ->
        Logger.warning(
          "Budget exceeded! Spent $#{Float.round(state.total_cost, 4)}, " <>
            "budget is $#{state.budget} (over by $#{Float.round(amount, 4)})"
        )

      {:warning, remaining} ->
        Logger.info(
          "Budget warning: $#{Float.round(remaining, 4)} remaining " <>
            "(spent $#{Float.round(state.total_cost, 4)} of $#{state.budget})"
        )

      :ok ->
        :ok
    end
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3600,
    do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"

  defp format_duration(seconds),
    do: "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"

  defp format_budget_status(:ok), do: "Within budget"

  defp format_budget_status({:warning, remaining}),
    do: "Warning: $#{Float.round(remaining, 4)} remaining"

  defp format_budget_status({:exceeded, amount}), do: "EXCEEDED by $#{Float.round(amount, 4)}"

  defp format_by_model(by_model) do
    by_model
    |> Enum.sort_by(fn {_model, stats} -> stats.cost end, :desc)
    |> Enum.map_join("\n", fn {model, stats} ->
      "  #{model}:\n" <>
        "    Cost: $#{Float.round(stats.cost, 6)}\n" <>
        "    Tokens: #{stats.tokens}\n" <>
        "    Requests: #{stats.requests}"
    end)
  end

  defp format_by_session(by_session) do
    by_session
    |> Enum.sort_by(fn {_session, stats} -> stats.cost end, :desc)
    |> Enum.take(10)
    |> Enum.map_join("\n", fn {session_id, stats} ->
      "  #{session_id}:\n" <>
        "    Cost: $#{Float.round(stats.cost, 6)}\n" <>
        "    Tokens: #{stats.tokens}\n" <>
        "    Requests: #{stats.requests}"
    end)
  end
end
