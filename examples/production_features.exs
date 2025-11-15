# Production Features Examples for Openrouter.ex
#
# This file demonstrates production-ready features including:
# - Content builders for multimodal input
# - Retry logic with exponential backoff
# - Telemetry for observability
#
# To run these examples:
#   export OPENROUTER_API_KEY="or-..."
#   mix run examples/production_features.exs

# Example 1: Telemetry Integration
IO.puts("\n=== Example 1: Telemetry ===")

# Attach default telemetry handler for logging
Openrouter.Telemetry.attach_default_handler(level: :info)

{:ok, response} = Openrouter.chat(
  "What is 2 + 2?",
  model: "openai/gpt-4"
)

IO.puts("Response: #{response.content}")
IO.puts("(Check logs above for telemetry events)")

# Detach handler
Openrouter.Telemetry.detach_default_handler()

# Example 2: Retry Logic
IO.puts("\n=== Example 2: Automatic Retry ===")

# This will automatically retry on failures with exponential backoff
result = Openrouter.Retry.with_retry(
  fn ->
    Openrouter.chat("Tell me a joke", model: "openai/gpt-4")
  end,
  max_attempts: 3,
  base_delay: 1000,
  retry_on: [:rate_limit, :server_error, :timeout]
)

case result do
  {:ok, response} ->
    IO.puts("✓ Request succeeded (possibly after retries)")
    IO.puts("Response: #{response.content}")

  {:error, error} ->
    IO.puts("✗ Request failed after all retries: #{error.message}")
end

# Example 3: Content Builders - Images
IO.puts("\n=== Example 3: Image Analysis (Content Builders) ===")

# Using image URL
content = [
  Openrouter.Content.text("What's in this image?"),
  Openrouter.Content.image_url("https://picsum.photos/400/300", detail: "high")
]

{:ok, response} = Openrouter.chat(
  [%{role: :user, content: content}],
  model: "anthropic/claude-3.5-sonnet"
)

IO.puts("Image analysis: #{response.content}")

# Example 4: Local Image with Base64
IO.puts("\n=== Example 4: Local Image Analysis ===")

# Note: This requires an actual image file
# Uncomment if you have an image file:
#
# image_data = File.read!("path/to/image.jpg")
# content = [
#   Openrouter.Content.text("Describe this image in detail"),
#   Openrouter.Content.image(image_data, format: :jpeg)
# ]
#
# {:ok, response} = Openrouter.chat(
#   [%{role: :user, content: content}],
#   model: "openai/gpt-4-vision"
# )
#
# IO.puts("Description: #{response.content}")

IO.puts("(Skipped - requires local image file)")

# Example 5: Content Builder Helper
IO.puts("\n=== Example 5: Content Builder Helper ===")

# Build complex multimodal content easily
content = Openrouter.Content.build([
  text: "Analyze these images and tell me what they have in common",
  image_url: "https://picsum.photos/400/300",
  image_url: "https://picsum.photos/400/301"
])

{:ok, response} = Openrouter.chat(
  [%{role: :user, content: content}],
  model: "anthropic/claude-3.5-sonnet"
)

IO.puts("Analysis: #{response.content}")

# Example 6: PDF Analysis
IO.puts("\n=== Example 6: PDF Document Analysis ===")

content = [
  Openrouter.Content.text("Summarize this document"),
  Openrouter.Content.pdf("https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf")
]

# Note: Not all models support PDF. This is model-dependent.
IO.puts("(Skipped - requires model with PDF support)")

# Example 7: Retry with Custom Error Handling
IO.puts("\n=== Example 7: Custom Retry Logic ===")

defmodule CustomRetryExample do
  def make_request_with_custom_retry do
    Openrouter.Retry.with_retry(
      fn ->
        # Simulate making a request
        Openrouter.chat("What is Elixir?", model: "openai/gpt-4")
      end,
      max_attempts: 5,
      base_delay: 500,
      max_delay: 10_000,
      retry_on: [:rate_limit, :server_error],
      jitter: true
    )
  end
end

case CustomRetryExample.make_request_with_custom_retry() do
  {:ok, response} ->
    IO.puts("✓ Success!")
    IO.puts("Response: #{String.slice(response.content, 0, 100)}...")

  {:error, error} ->
    IO.puts("✗ Failed: #{error.message}")
end

# Example 8: Custom Telemetry Handler
IO.puts("\n=== Example 8: Custom Telemetry Handler ===")

defmodule CustomTelemetryHandler do
  require Logger

  def attach do
    :telemetry.attach_many(
      "custom-openrouter-metrics",
      [
        [:openrouter, :request, :stop],
        [:openrouter, :request, :exception]
      ],
      &handle_event/4,
      %{}
    )
  end

  def detach do
    :telemetry.detach("custom-openrouter-metrics")
  end

  def handle_event([:openrouter, :request, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    tokens = get_in(metadata, [:tokens, "total_tokens"]) || 0

    Logger.info("📊 API Metrics",
      duration: "#{duration_ms}ms",
      model: metadata.model,
      tokens: tokens,
      cost_estimate: estimate_cost(tokens, metadata.model)
    )
  end

  def handle_event([:openrouter, :request, :exception], _measurements, metadata, _config) do
    Logger.error("❌ API Error", error: metadata.error_type)
  end

  defp estimate_cost(tokens, _model) do
    # Simplified cost estimation
    # Real implementation would use actual model pricing
    "$#{Float.round(tokens * 0.00001, 4)}"
  end
end

# Attach custom handler
CustomTelemetryHandler.attach()

{:ok, response} = Openrouter.chat(
  "Explain quantum computing in one sentence",
  model: "openai/gpt-4"
)

IO.puts("Response: #{response.content}")
IO.puts("(Check logs for custom metrics)")

# Cleanup
CustomTelemetryHandler.detach()

# Example 9: Combining All Production Features
IO.puts("\n=== Example 9: Complete Production Example ===")

defmodule ProductionExample do
  require Logger

  def analyze_image_with_retry(image_url, opts \\ []) do
    # Enable telemetry
    Openrouter.Telemetry.attach_default_handler(level: :info)

    # Build content
    content = Openrouter.Content.build([
      text: "Analyze this image professionally",
      image_url: image_url
    ])

    # Make request with retry
    result =
      Openrouter.Retry.with_retry(
        fn ->
          Openrouter.chat(
            [%{role: :user, content: content}],
            Keyword.merge([model: "anthropic/claude-3.5-sonnet"], opts)
          )
        end,
        max_attempts: 3,
        base_delay: 1000
      )

    # Cleanup
    Openrouter.Telemetry.detach_default_handler()

    result
  end
end

case ProductionExample.analyze_image_with_retry("https://picsum.photos/400/300") do
  {:ok, response} ->
    IO.puts("✓ Production request successful!")
    IO.puts("Analysis: #{String.slice(response.content, 0, 200)}...")

  {:error, error} ->
    IO.puts("✗ Production request failed: #{error.message}")
end

IO.puts("\n=== All Production Examples Complete ===")
