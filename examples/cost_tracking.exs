#!/usr/bin/env elixir
#
# Cost Tracking and Budgeting Example
#
# This example demonstrates cost tracking features:
# - Enabling cost tracking in API requests
# - Using CostTracker for budget management
# - Token counting and cost estimation
# - Per-model and per-session tracking
# - Usage reports and analytics
#
# Run with: mix run examples/cost_tracking.exs

Mix.install([{:openrouter, path: "."}])

alias Openrouter.{CostTracker, TokenCounter}
require Logger

IO.puts("\n=== Cost Tracking and Budgeting Example ===\n")

# ============================================================================
# Example 1: Basic Cost Tracking
# ============================================================================

IO.puts("1. Basic Cost Tracking")
IO.puts("   Enabling cost tracking in API responses\n")

# Enable cost tracking with usage: %{include: true}
{:ok, response} =
  Openrouter.chat(
    "Explain Elixir in one sentence",
    model: "openai/gpt-3.5-turbo",
    usage: %{include: true}
  )

IO.puts("Response: #{response.content}\n")

if response.usage do
  IO.puts("Usage Information:")
  IO.puts("  Tokens: #{response.usage.total_tokens}")
  IO.puts("  Prompt: #{response.usage.prompt_tokens}")
  IO.puts("  Completion: #{response.usage.completion_tokens}")

  if response.usage.total_cost do
    IO.puts("  Cost: $#{Float.round(response.usage.total_cost, 6)}")
  end

  if response.usage.native_tokens_prompt do
    IO.puts("  Native tokens (billing): #{response.usage.native_tokens_prompt + response.usage.native_tokens_completion}")
  end

  IO.puts("")
else
  IO.puts("No usage data (cost tracking not enabled)\n")
end

# ============================================================================
# Example 2: Token Counting and Cost Estimation
# ============================================================================

IO.puts("2. Token Counting and Cost Estimation")
IO.puts("   Estimate costs before making API calls\n")

messages = [
  %{role: :system, content: "You are a helpful assistant"},
  %{role: :user, content: "Write a short poem about Elixir programming"}
]

# Estimate tokens
input_tokens = TokenCounter.count_messages(messages)
IO.puts("Estimated input tokens: #{input_tokens}")

# Estimate cost
{:ok, estimate} =
  TokenCounter.estimate_cost(
    messages,
    model: "openai/gpt-4",
    max_tokens: 200
  )

IO.puts("\n#{TokenCounter.format_estimate(estimate)}")

# Make actual request with cost tracking
{:ok, response} =
  Openrouter.chat(
    messages,
    model: "openai/gpt-4",
    max_tokens: 200,
    usage: %{include: true}
  )

IO.puts("Actual cost: $#{Float.round(response.usage.total_cost || 0.0, 6)}")
IO.puts("Actual tokens: #{response.usage.total_tokens}\n")

# ============================================================================
# Example 3: Cost Tracker with Budget
# ============================================================================

IO.puts("3. Cost Tracker with Budget")
IO.puts("   Track spending and enforce budgets\n")

# Start tracker with $1.00 budget
{:ok, tracker} = CostTracker.start_link(budget: 1.00)

# Make several requests
models = ["openai/gpt-3.5-turbo", "anthropic/claude-3-haiku", "google/gemini-2.0-flash"]

Enum.each(models, fn model ->
  IO.puts("Testing #{model}...")

  case CostTracker.check_budget(tracker) do
    :ok ->
      {:ok, response} =
        Openrouter.chat(
          "What is #{model}?",
          model: model,
          max_tokens: 50,
          usage: %{include: true}
        )

      :ok = CostTracker.track(tracker, response)

      if response.usage.total_cost do
        IO.puts("  Cost: $#{Float.round(response.usage.total_cost, 6)}")
      end

    {:exceeded, amount} ->
      IO.puts("  Skipped - budget exceeded by $#{Float.round(amount, 4)}")

    {:warning, remaining} ->
      IO.puts("  Warning - only $#{Float.round(remaining, 4)} remaining")
  end
end)

# Get usage summary
usage = CostTracker.get_usage(tracker)
IO.puts("\nTotal Spending:")
IO.puts("  Cost: $#{Float.round(usage.total_cost, 6)}")
IO.puts("  Requests: #{usage.request_count}")
IO.puts("  Avg cost/request: $#{Float.round(usage.average_cost_per_request, 6)}\n")

# ============================================================================
# Example 4: Per-Model Cost Tracking
# ============================================================================

IO.puts("4. Per-Model Cost Tracking")
IO.puts("   Track costs by model\n")

{:ok, tracker} = CostTracker.start_link()

# Compare different models
test_prompt = "Say hello in 3 words"

test_models = [
  "openai/gpt-4o-mini",
  "openai/gpt-3.5-turbo",
  "anthropic/claude-3-haiku",
  "google/gemini-2.0-flash"
]

Enum.each(test_models, fn model ->
  {:ok, response} =
    Openrouter.chat(
      test_prompt,
      model: model,
      max_tokens: 20,
      usage: %{include: true}
    )

  :ok = CostTracker.track(tracker, response)
end)

# Get detailed stats
stats = CostTracker.get_stats(tracker)

IO.puts("Cost by Model:")

stats.by_model
|> Enum.sort_by(fn {_model, s} -> s.cost end, :desc)
|> Enum.each(fn {model, model_stats} ->
  IO.puts("  #{model}:")
  IO.puts("    Cost: $#{Float.round(model_stats.cost, 6)}")
  IO.puts("    Tokens: #{model_stats.tokens}")
  IO.puts("    Requests: #{model_stats.requests}")
end)

IO.puts("")

# ============================================================================
# Example 5: Session-Based Tracking
# ============================================================================

IO.puts("5. Session-Based Cost Tracking")
IO.puts("   Track costs per conversation/session\n")

{:ok, tracker} = CostTracker.start_link()

# Simulate multiple conversation sessions
sessions = ["session-A", "session-B", "session-C"]

Enum.each(sessions, fn session_id ->
  # Each session makes 2-3 requests
  num_requests = :rand.uniform(3)

  Enum.each(1..num_requests, fn _i ->
    {:ok, response} =
      Openrouter.chat(
        "Short message #{:rand.uniform(100)}",
        model: "openai/gpt-3.5-turbo",
        max_tokens: 30,
        usage: %{include: true}
      )

    :ok = CostTracker.track(tracker, response, session_id: session_id)
  end)
end)

# Get stats per session
stats = CostTracker.get_stats(tracker)

IO.puts("Cost by Session:")

Enum.each(stats.by_session, fn {session_id, session_stats} ->
  IO.puts("  #{session_id}:")
  IO.puts("    Cost: $#{Float.round(session_stats.cost, 6)}")
  IO.puts("    Requests: #{session_stats.requests}")
end)

IO.puts("")

# ============================================================================
# Example 6: Usage Report
# ============================================================================

IO.puts("6. Detailed Usage Report")
IO.puts("   Generate comprehensive usage reports\n")

{:ok, tracker} = CostTracker.start_link(budget: 5.00)

# Make various requests
requests = [
  {"openai/gpt-4", "Explain AI"},
  {"openai/gpt-3.5-turbo", "What is ML?"},
  {"anthropic/claude-3-sonnet", "Define neural networks"},
  {"openai/gpt-4", "Summarize deep learning"},
  {"google/gemini-2.0-flash", "What is NLP?"}
]

Enum.each(requests, fn {model, prompt} ->
  {:ok, response} =
    Openrouter.chat(
      prompt,
      model: model,
      max_tokens: 50,
      usage: %{include: true}
    )

  :ok = CostTracker.track(tracker, response)
end)

# Generate report
report = CostTracker.format_report(tracker)
IO.puts(report)

# ============================================================================
# Example 7: Cost Tracking with Conversations
# ============================================================================

IO.puts("7. Cost Tracking with Conversations")
IO.puts("   Track costs for multi-turn conversations\n")

{:ok, tracker} = CostTracker.start_link()

# Start a conversation
{:ok, conv} =
  Openrouter.Conversation.start(
    model: "openai/gpt-3.5-turbo",
    system: "You are a helpful assistant. Be very concise."
  )

# Multi-turn conversation
questions = [
  "What is Elixir?",
  "What are its main features?",
  "Is it good for web development?"
]

conv =
  Enum.reduce(questions, conv, fn question, c ->
    c = Openrouter.Conversation.user(c, question)

    {:ok, c, response} =
      Openrouter.Conversation.complete(c, max_tokens: 100, usage: %{include: true})

    # Track each response
    :ok = CostTracker.track(tracker, response, session_id: c.id)

    IO.puts("Q: #{question}")
    IO.puts("A: #{response.content}")

    if response.usage.total_cost do
      IO.puts("   (Cost: $#{Float.round(response.usage.total_cost, 6)})")
    end

    IO.puts("")

    c
  end)

# Get total conversation cost
session_stats = CostTracker.get_session_stats(tracker, conv.id)

IO.puts("Conversation Total:")
IO.puts("  Cost: $#{Float.round(session_stats.cost, 6)}")
IO.puts("  Tokens: #{session_stats.tokens}")
IO.puts("  Messages: #{session_stats.requests}\n")

# ============================================================================
# Example 8: Custom Pricing for Testing
# ============================================================================

IO.puts("8. Custom Pricing")
IO.puts("   Override model pricing for testing\n")

# Set custom pricing for a model
:ok =
  TokenCounter.set_pricing("custom/test-model", %{
    prompt: 0.10,
    completion: 0.20
  })

# Estimate cost with custom pricing
{:ok, estimate} =
  TokenCounter.estimate_cost(
    [%{role: :user, content: "Test message"}],
    model: "custom/test-model",
    max_tokens: 100
  )

IO.puts("Custom model estimate:")
IO.puts(TokenCounter.format_estimate(estimate))

# ============================================================================
# Example 9: Budget Warnings and Alerts
# ============================================================================

IO.puts("9. Budget Warnings")
IO.puts("   Get alerts when approaching budget limits\n")

# Start tracker with small budget and 80% warning threshold
{:ok, tracker} = CostTracker.start_link(
  budget: 0.10,
  budget_warning_threshold: 0.8
)

# Make requests until budget warning/exceeded
Enum.each(1..20, fn i ->
  status = CostTracker.check_budget(tracker)

  case status do
    :ok ->
      {:ok, response} =
        Openrouter.chat(
          "Message #{i}",
          model: "openai/gpt-3.5-turbo",
          max_tokens: 20,
          usage: %{include: true}
        )

      :ok = CostTracker.track(tracker, response)

    {:warning, remaining} ->
      IO.puts("⚠️  Budget warning! $#{Float.round(remaining, 4)} remaining")

      {:ok, response} =
        Openrouter.chat(
          "Message #{i}",
          model: "openai/gpt-3.5-turbo",
          max_tokens: 20,
          usage: %{include: true}
        )

      :ok = CostTracker.track(tracker, response)

    {:exceeded, amount} ->
      IO.puts("🛑 Budget exceeded by $#{Float.round(amount, 4)}. Stopping.")
      IO.puts("")
      throw(:budget_exceeded)
  end
end)
catch
  :budget_exceeded -> :ok
end

usage = CostTracker.get_usage(tracker)
IO.puts("Final spending: $#{Float.round(usage.total_cost, 6)}\n")

# ============================================================================
# Example 10: Production Best Practices
# ============================================================================

IO.puts("10. Production Best Practices\n")

IO.puts("Best Practices for Cost Tracking:")

IO.puts("\n1. Always Enable Cost Tracking:")
IO.puts("   - Add usage: %{include: true} to every request")
IO.puts("   - Store cost data in your database")
IO.puts("   - Track costs per user/tenant")

IO.puts("\n2. Set Budgets:")
IO.puts("   - Per-user spending limits")
IO.puts("   - Per-session/conversation limits")
IO.puts("   - Daily/monthly organization limits")

IO.puts("\n3. Monitor and Alert:")
IO.puts("   - Set up telemetry for cost tracking")
IO.puts("   - Alert when budgets are approaching")
IO.puts("   - Track cost trends over time")

IO.puts("\n4. Optimize Costs:")
IO.puts("   - Use cheaper models when possible")
IO.puts("   - Limit max_tokens appropriately")
IO.puts("   - Cache responses when applicable")
IO.puts("   - Use prompt engineering to reduce tokens")

IO.puts("\n5. Estimate Before Calling:")
IO.puts("   - Use TokenCounter to estimate costs")
IO.puts("   - Warn users of high-cost operations")
IO.puts("   - Implement request size limits")

IO.puts("\n6. Track by Dimension:")
IO.puts("   - By user/customer")
IO.puts("   - By feature/use case")
IO.puts("   - By model")
IO.puts("   - By session/conversation")

IO.puts("\n7. Reporting:")
IO.puts("   - Generate daily/weekly cost reports")
IO.puts("   - Compare estimated vs actual costs")
IO.puts("   - Analyze cost per feature")
IO.puts("   - Track ROI of AI features")

IO.puts("")

IO.puts("=== Cost Tracking Example Complete ===\n")
