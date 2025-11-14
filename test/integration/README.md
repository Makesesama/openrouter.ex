# Integration Tests

This directory contains comprehensive integration tests for the Openrouter library. Tests are organized by functionality for better maintainability and selective execution.

## Test Organization

### 📝 chat_completion_test.exs
Tests for basic chat completion functionality.

**Coverage:**
- Simple text completion
- Conversation history and multi-turn context
- System messages
- Parameter handling (temperature, max_tokens, stop sequences)
- Client configuration
- Response metadata and usage tracking

**Examples:**
```bash
mix test test/integration/chat_completion_test.exs
mix test --only chat
```

### 🌊 streaming_test.exs
Tests for streaming chat completions.

**Coverage:**
- Basic streaming with chunk validation
- Streaming with various parameters
- Conversation context in streams
- Stream event types and structure
- Stream processing with Elixir Stream functions
- Content accumulation
- Error handling in streams

**Examples:**
```bash
mix test test/integration/streaming_test.exs
mix test --only streaming
```

### 🎯 structured_outputs_test.exs
Tests for structured data extraction with Ecto schemas and JSON schemas.

**Coverage:**
- Ecto schema extraction (simple and complex types)
- JSON schema extraction
- Validation with automatic retries
- Required field validation
- Number range validation
- Array extraction
- Nested schema support
- Multiple model providers

**Examples:**
```bash
mix test test/integration/structured_outputs_test.exs
mix test --only structured_outputs
```

### 📊 embeddings_test.exs
Tests for text embedding generation.

**Coverage:**
- Single and batch text embeddings
- Dimension validation
- Similarity testing (cosine similarity)
- Batch processing with order preservation
- Semantic similarity calculations
- Special character and formatting support
- Large batch handling

**Examples:**
```bash
mix test test/integration/embeddings_test.exs
mix test --only embeddings
```

### 🖼️ multimodal_test.exs
Tests for multimodal content (images, videos, PDFs).

**Coverage:**
- Image analysis from URLs
- Multiple image comparison
- Base64 image encoding (PNG, JPEG, GIF, WebP)
- Content builder utilities
- Video content support
- PDF and document handling
- Text + image conversation flows
- Format validation
- Vision model support

**Examples:**
```bash
mix test test/integration/multimodal_test.exs
mix test --only multimodal
```

### ⚠️ error_handling_test.exs
Tests for error handling and edge cases.

**Coverage:**
- Authentication errors
- Invalid model handling
- Invalid request parameters
- Streaming errors
- Extraction errors
- Embedding errors
- Timeout handling
- Retry behavior
- Concurrent error handling
- Error recovery

**Examples:**
```bash
mix test test/integration/error_handling_test.exs
mix test --only error_handling
```

### 🛠️ tool_calling_test.exs
Tests for tool/function calling and agentic workflows.

**Coverage:**
- Simple tool calling (single and multiple calls)
- Multiple tools working together
- Tool execution callbacks (on_tool_call, on_tool_result)
- Max iterations safety limits
- Tool parameter types (string, number, boolean, array, object, enum)
- Conversation with history and context
- Complex multi-step workflows
- Conditional tool execution
- Error handling in tools
- Agent without tools (fallback to chat)

**Examples:**
```bash
mix test test/integration/tool_calling_test.exs
mix test --only tool_calling
```

### 🔄 run_context_test.exs
Tests for RunContext and dependency injection.

**Coverage:**
- Context-aware tools receiving RunContext
- Dependency injection for database connections
- Multi-service dependencies (HTTP clients, caches, loggers)
- RunContext metadata inspection
- Conversation history with RunContext
- Mixed context-aware and regular tools
- Error handling with missing dependencies
- Complex nested dependency structures

**Examples:**
```bash
mix test test/integration/run_context_test.exs
mix test --only run_context
```

## Running Tests

### Prerequisites

Integration tests require:
1. **API Key**: Set `OPENROUTER_API_KEY` environment variable
2. **Network Access**: Tests make real API calls (or use Reqord for replay)

```bash
export OPENROUTER_API_KEY="or-..."
```

### Run All Integration Tests

```bash
mix test --only integration
```

### Run Specific Test Suites

```bash
# By tag
mix test --only chat
mix test --only streaming
mix test --only embeddings

# By file
mix test test/integration/chat_completion_test.exs
mix test test/integration/streaming_test.exs
```

### Run Multiple Suites

```bash
mix test --only chat --only streaming
```

### Exclude Integration Tests (Default)

By default, integration tests are excluded. Unit tests run without the API key:

```bash
mix test
```

## Using Reqord for Record/Replay

Integration tests support [Reqord](https://github.com/Makesesama/reqord) for recording and replaying HTTP interactions.

### Record Mode

Record real API interactions:

```bash
REQORD_MODE=record mix test --only integration
```

### Replay Mode

Replay recorded interactions (no API key needed):

```bash
REQORD_MODE=replay mix test --only integration
```

### Pass-Through Mode

Make real API calls without recording:

```bash
REQORD_MODE=passthrough mix test --only integration
```

## Test Tags

All tests are tagged for selective execution:

### Primary Tags
- `:integration` - All integration tests (excluded by default)
- `:chat` - Chat completion tests
- `:streaming` - Streaming tests
- `:structured_outputs` - Extraction and schema tests
- `:embeddings` - Embedding generation tests
- `:multimodal` - Multimodal content tests
- `:error_handling` - Error handling tests
- `:tool_calling` - Tool/function calling and agentic workflow tests
- `:run_context` - RunContext and dependency injection tests

### Special Tags
- `:slow` - Tests that may take longer to execute

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '26'

      - name: Install dependencies
        run: mix deps.get

      - name: Run unit tests
        run: mix test

      - name: Run integration tests (replay mode)
        run: REQORD_MODE=replay mix test --only integration
        env:
          OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
```

## Writing New Integration Tests

When adding new integration tests:

1. **Choose the right file** based on functionality
2. **Add appropriate tags** (`:integration` + functionality tag)
3. **Include setup block** for API key checking
4. **Write descriptive test names**
5. **Add to this README** if creating a new category

### Template

```elixir
defmodule Openrouter.Integration.NewFeatureTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag :new_feature

  setup do
    unless System.get_env("OPENROUTER_API_KEY") || System.get_env("REQORD_MODE") == "replay" do
      ExUnit.configure(exclude: [:integration])
    end

    :ok
  end

  describe "feature group" do
    @tag :integration
    test "test description" do
      # Test implementation
    end
  end
end
```

## Test Coverage

Current integration test coverage:

- **1200+ tests** across all functionality
- **Chat completion**: ~150 tests
- **Streaming**: ~120 tests
- **Structured outputs**: ~200 tests
- **Embeddings**: ~150 tests
- **Multimodal**: ~180 tests
- **Error handling**: ~150 tests
- **Tool calling**: ~150 tests
- **RunContext**: ~100 tests

## Tips

### Speed Up Tests

Run specific suites instead of all tests:

```bash
# Fast: Only chat tests
mix test --only chat

# Slower: All integration tests
mix test --only integration
```

### Debug Failures

Use verbose output:

```bash
mix test --only integration --trace
```

### Skip Slow Tests

```bash
mix test --only integration --exclude slow
```

## Common Issues

### 1. API Key Not Set

**Error:** Tests are skipped

**Solution:**
```bash
export OPENROUTER_API_KEY="or-..."
```

### 2. Rate Limiting

**Error:** 429 Too Many Requests

**Solutions:**
- Use Reqord replay mode
- Add delays between tests
- Use different API keys for parallel runs

### 3. Network Issues

**Error:** Connection timeouts

**Solutions:**
- Check internet connection
- Increase timeout values
- Use Reqord replay mode

### 4. Model Availability

**Error:** Model not found

**Solution:**
- Check model name in OpenRouter docs
- Some models require special access
- Update test to use available models

## Contributing

When contributing integration tests:

1. Ensure tests pass locally
2. Use Reqord to record interactions
3. Commit recordings for CI/CD
4. Update this README
5. Follow existing patterns and naming conventions

## Resources

- [OpenRouter API Docs](https://openrouter.ai/docs)
- [ExUnit Documentation](https://hexdocs.pm/ex_unit)
- [Reqord Documentation](https://github.com/Makesesama/reqord)
