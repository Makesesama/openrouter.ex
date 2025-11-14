#!/usr/bin/env elixir
#
# Web Search Integration Example
#
# This example demonstrates integrating web search capabilities with LLMs:
# - Using tools to search the web
# - Extracting structured data from search results
# - Combining search with other tools
# - Multi-step research workflows
#
# Note: This example uses simulated search results. In production, integrate
# with real search APIs like Google Custom Search, Bing, or Brave Search.
#
# Run with: mix run examples/web_search.exs

Mix.install([{:openrouter, path: "."}])

require Logger

IO.puts("\n=== Web Search Integration Example ===\n")

# ============================================================================
# Mock Search API (Replace with real search API in production)
# ============================================================================

defmodule MockSearchAPI do
  @moduledoc """
  Simulated search API for demonstration purposes.

  In production, replace with real search APIs:
  - Google Custom Search: https://developers.google.com/custom-search
  - Bing Search API: https://www.microsoft.com/en-us/bing/apis/bing-web-search-api
  - Brave Search API: https://brave.com/search/api/
  - DuckDuckGo API (free, limited): https://duckduckgo.com/api
  """

  def search(query, _opts \\ []) do
    # Simulate API delay
    Process.sleep(100)

    # Return mock results based on query keywords
    results =
      cond do
        String.contains?(String.downcase(query), "elixir") ->
          [
            %{
              title: "Elixir Programming Language",
              url: "https://elixir-lang.org",
              snippet:
                "Elixir is a dynamic, functional language for building scalable applications. It leverages the Erlang VM."
            },
            %{
              title: "Getting Started with Elixir",
              url: "https://elixir-lang.org/getting-started",
              snippet:
                "Learn Elixir fundamentals including pattern matching, processes, and OTP."
            },
            %{
              title: "Elixir School",
              url: "https://elixirschool.com",
              snippet:
                "Free lessons about the Elixir programming language with translations in multiple languages."
            }
          ]

        String.contains?(String.downcase(query), "phoenix") ->
          [
            %{
              title: "Phoenix Framework",
              url: "https://phoenixframework.org",
              snippet:
                "Phoenix is a web framework built with Elixir, providing real-time features and productivity."
            },
            %{
              title: "Phoenix LiveView",
              url: "https://hexdocs.pm/phoenix_live_view",
              snippet:
                "Build rich, real-time user experiences with server-rendered HTML in Phoenix."
            }
          ]

        String.contains?(String.downcase(query), "weather") ->
          [
            %{
              title: "Weather Forecast",
              url: "https://weather.example.com",
              snippet: "Current weather: Sunny, 72°F. High: 78°F, Low: 65°F."
            },
            %{
              title: "Weather.com",
              url: "https://weather.com",
              snippet: "Get accurate weather forecasts for your location."
            }
          ]

        true ->
          [
            %{
              title: "Search Result for: #{query}",
              url: "https://example.com/result1",
              snippet: "This is a simulated search result for '#{query}'."
            },
            %{
              title: "Another Result",
              url: "https://example.com/result2",
              snippet: "More information about #{query} can be found here."
            }
          ]
      end

    {:ok, results}
  end

  def fetch_page(url, _opts \\ []) do
    # Simulate fetching page content
    Process.sleep(100)

    content =
      cond do
        String.contains?(url, "elixir-lang.org") ->
          """
          Elixir is a dynamic, functional language designed for building scalable
          and maintainable applications. It leverages the Erlang VM, known for
          running low-latency, distributed and fault-tolerant systems.
          """

        String.contains?(url, "phoenixframework.org") ->
          """
          Phoenix is a web development framework written in Elixir which implements
          the server-side Model View Controller (MVC) pattern. Built on Elixir and
          the Erlang VM, Phoenix provides incredibly high performance and productivity.
          """

        true ->
          "Page content for #{url}"
      end

    {:ok, content}
  end
end

# ============================================================================
# Example 1: Basic Web Search Tool
# ============================================================================

IO.puts("1. Basic Web Search Tool")
IO.puts("   LLM can search the web to answer questions\n")

search_tool =
  Openrouter.Tool.new(
    :web_search,
    "Search the web for information",
    fn %{query: query} ->
      {:ok, results} = MockSearchAPI.search(query)

      formatted =
        results
        |> Enum.with_index(1)
        |> Enum.map(fn {result, idx} ->
          """
          #{idx}. #{result.title}
          URL: #{result.url}
          #{result.snippet}
          """
        end)
        |> Enum.join("\n")

      {:ok, formatted}
    end,
    parameters: %{
      query: [type: :string, required: true, description: "Search query"]
    }
  )

{:ok, result} =
  Openrouter.Agent.run(
    "What is Elixir and what are its main features?",
    model: "openai/gpt-3.5-turbo",
    tools: [search_tool],
    system: "You are a helpful assistant. Search the web to answer questions accurately."
  )

IO.puts("Answer: #{result.content}\n")

# ============================================================================
# Example 2: Multi-Tool Search Agent
# ============================================================================

IO.puts("2. Multi-Tool Search Agent")
IO.puts("   Combine web search with other tools\n")

search_tool =
  Openrouter.Tool.new(
    :search,
    "Search the web",
    fn %{query: query} ->
      {:ok, results} = MockSearchAPI.search(query)

      formatted =
        Enum.map_join(results, "\n\n", fn r ->
          "[#{r.title}](#{r.url})\n#{r.snippet}"
        end)

      {:ok, formatted}
    end,
    parameters: %{query: [type: :string, required: true]}
  )

fetch_tool =
  Openrouter.Tool.new(
    :fetch_page,
    "Fetch full content from a URL",
    fn %{url: url} ->
      {:ok, content} = MockSearchAPI.fetch_page(url)
      {:ok, content}
    end,
    parameters: %{
      url: [type: :string, required: true, description: "URL to fetch"]
    }
  )

summarize_tool =
  Openrouter.Tool.new(
    :summarize,
    "Summarize text into key points",
    fn %{text: text} ->
      # In production, might use a separate LLM call or extractive summarization
      summary = String.slice(text, 0..200) <> "..."
      {:ok, summary}
    end,
    parameters: %{
      text: [type: :string, required: true, description: "Text to summarize"]
    }
  )

{:ok, result} =
  Openrouter.Agent.run(
    "Search for information about Phoenix Framework and give me a detailed summary",
    model: "openai/gpt-3.5-turbo",
    tools: [search_tool, fetch_tool, summarize_tool],
    system:
      "You are a research assistant. Use tools to search, fetch, and summarize information."
  )

IO.puts("Research Result: #{result.content}\n")

# ============================================================================
# Example 3: Context-Aware Search with Conversation History
# ============================================================================

IO.puts("3. Context-Aware Search")
IO.puts("   Search tool accesses conversation history via RunContext\n")

defmodule SearchDeps do
  defstruct [:api_key, :search_history, :max_results]
end

context_search_tool =
  Openrouter.Tool.new(
    :contextual_search,
    "Search with awareness of previous searches",
    fn ctx, %{query: query} ->
      # Access deps
      max_results = ctx.deps.max_results || 3

      # Check search history from context metadata
      previous_queries = ctx.deps.search_history || []

      # Enhance query based on context
      enhanced_query =
        if length(previous_queries) > 0 do
          "#{query} (related to: #{Enum.join(previous_queries, ", ")})"
        else
          query
        end

      IO.puts("  Searching: #{enhanced_query}")

      {:ok, results} = MockSearchAPI.search(query, limit: max_results)

      formatted =
        Enum.map_join(results, "\n", fn r ->
          "- #{r.title}: #{r.snippet}"
        end)

      {:ok, formatted}
    end,
    parameters: %{
      query: [type: :string, required: true]
    },
    context_aware: true
  )

deps = %SearchDeps{
  api_key: "mock_key",
  search_history: [],
  max_results: 2
}

{:ok, result} =
  Openrouter.Agent.run(
    "Search for Elixir, then tell me about its web framework",
    model: "openai/gpt-3.5-turbo",
    tools: [context_search_tool],
    deps: deps
  )

IO.puts("Answer: #{result.content}\n")

# ============================================================================
# Example 4: Structured Data Extraction from Search Results
# ============================================================================

IO.puts("4. Structured Data Extraction")
IO.puts("   Extract structured information from search results\n")

defmodule SearchResultSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:query, :string)
    field(:sources, {:array, :string})
    field(:summary, :string)
    field(:key_facts, {:array, :string})
    field(:confidence, :string)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:query, :sources, :summary, :key_facts, :confidence])
    |> validate_required([:query, :summary, :key_facts])
    |> validate_inclusion(:confidence, ["high", "medium", "low"])
  end
end

search_tool =
  Openrouter.Tool.new(
    :search,
    "Search the web",
    fn %{query: query} ->
      {:ok, results} = MockSearchAPI.search(query)

      formatted =
        Enum.map_join(results, "\n", fn r ->
          "#{r.title} (#{r.url}): #{r.snippet}"
        end)

      {:ok, formatted}
    end,
    parameters: %{query: [type: :string, required: true]}
  )

prompt = """
Search for information about "Elixir programming language" and extract structured data.

Use the search tool, then return structured information about what you found.
"""

{:ok, research_data} =
  Openrouter.Agent.extract(
    prompt,
    schema: SearchResultSchema,
    model: "openai/gpt-3.5-turbo",
    tools: [search_tool]
  )

IO.puts("Extracted Research Data:")
IO.puts("  Query: #{research_data.query}")
IO.puts("  Summary: #{research_data.summary}")
IO.puts("  Key Facts:")
Enum.each(research_data.key_facts, fn fact -> IO.puts("    - #{fact}") end)
IO.puts("  Sources: #{Enum.join(research_data.sources, ", ")}")
IO.puts("  Confidence: #{research_data.confidence}\n")

# ============================================================================
# Example 5: Multi-Step Research Workflow
# ============================================================================

IO.puts("5. Multi-Step Research Workflow")
IO.puts("   Agent performs complex research across multiple searches\n")

search_tool =
  Openrouter.Tool.new(
    :search,
    "Search for information",
    fn %{query: query} ->
      {:ok, results} = MockSearchAPI.search(query)
      formatted = Enum.map_join(results, "\n", fn r -> "#{r.title}: #{r.snippet}" end)
      {:ok, formatted}
    end,
    parameters: %{query: [type: :string, required: true]}
  )

compare_tool =
  Openrouter.Tool.new(
    :compare,
    "Compare two topics",
    fn %{topic1: t1, topic2: t2} ->
      result = """
      Comparison of #{t1} vs #{t2}:
      - Both are used for web development
      - #{t1} focuses on functional programming
      - #{t2} focuses on object-oriented programming
      """

      {:ok, result}
    end,
    parameters: %{
      topic1: [type: :string, required: true],
      topic2: [type: :string, required: true]
    }
  )

{:ok, result} =
  Openrouter.Agent.run(
    """
    Research task: Compare Elixir and Phoenix.
    1. Search for information about each
    2. Identify their relationship
    3. Provide a comprehensive comparison
    """,
    model: "openai/gpt-3.5-turbo",
    tools: [search_tool, compare_tool],
    max_iterations: 8
  )

IO.puts("Research Report: #{result.content}\n")

# ============================================================================
# Example 6: Search with Conversation Server (Stateful)
# ============================================================================

IO.puts("6. Stateful Search Agent")
IO.puts("   Maintain search context across multiple queries\n")

search_tool =
  Openrouter.Tool.new(
    :search,
    "Search the web",
    fn %{query: query} ->
      {:ok, results} = MockSearchAPI.search(query, limit: 2)
      formatted = Enum.map_join(results, "\n", fn r -> "#{r.title}: #{r.snippet}" end)
      {:ok, formatted}
    end,
    parameters: %{query: [type: :string, required: true]}
  )

{:ok, pid} =
  Openrouter.ConversationServer.start_link(
    model: "openai/gpt-3.5-turbo",
    tools: [search_tool],
    use_agent: true,
    system: "You are a research assistant. Search for information to answer questions."
  )

# First query
{:ok, response1} =
  Openrouter.ConversationServer.send_message(pid, "Search for information about Elixir")

IO.puts("Q1: Search for information about Elixir")
IO.puts("A1: #{response1.content}\n")

# Follow-up query (uses conversation context)
{:ok, response2} =
  Openrouter.ConversationServer.send_message(pid, "What frameworks are built with it?")

IO.puts("Q2: What frameworks are built with it?")
IO.puts("A2: #{response2.content}\n")

Openrouter.ConversationServer.stop(pid)

# ============================================================================
# Example 7: Search with Caching and Rate Limiting
# ============================================================================

IO.puts("7. Production Patterns")
IO.puts("   Caching, rate limiting, and error handling\n")

defmodule CachedSearchAPI do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{cache: %{}, call_count: 0, last_call: nil} end, name: __MODULE__)
  end

  def search(query) do
    state = Agent.get(__MODULE__, & &1)

    # Check cache
    if Map.has_key?(state.cache, query) do
      IO.puts("  ✓ Cache hit for: #{query}")
      {:ok, state.cache[query]}
    else
      # Rate limiting check
      if should_rate_limit?(state) do
        IO.puts("  ✗ Rate limited, waiting...")
        Process.sleep(1000)
      end

      # Perform search
      IO.puts("  → API call for: #{query}")
      {:ok, results} = MockSearchAPI.search(query)

      # Update cache and state
      Agent.update(__MODULE__, fn state ->
        %{
          state
          | cache: Map.put(state.cache, query, results),
            call_count: state.call_count + 1,
            last_call: System.system_time(:millisecond)
        }
      end)

      {:ok, results}
    end
  end

  defp should_rate_limit?(state) do
    case state.last_call do
      nil -> false
      last_call -> System.system_time(:millisecond) - last_call < 500
    end
  end

  def clear_cache do
    Agent.update(__MODULE__, fn state -> %{state | cache: %{}} end)
  end

  def stats do
    Agent.get(__MODULE__, fn state ->
      %{
        cache_size: map_size(state.cache),
        total_calls: state.call_count
      }
    end)
  end
end

# Start cache
{:ok, _pid} = CachedSearchAPI.start_link([])

cached_search_tool =
  Openrouter.Tool.new(
    :cached_search,
    "Search with caching",
    fn %{query: query} ->
      {:ok, results} = CachedSearchAPI.search(query)
      formatted = Enum.map_join(results, "\n", fn r -> "#{r.title}: #{r.snippet}" end)
      {:ok, formatted}
    end,
    parameters: %{query: [type: :string, required: true]}
  )

# First search (cache miss)
{:ok, _result1} =
  Openrouter.Agent.run(
    "Search for Elixir",
    model: "openai/gpt-3.5-turbo",
    tools: [cached_search_tool]
  )

# Second search (cache hit)
{:ok, _result2} =
  Openrouter.Agent.run(
    "Search for Elixir again",
    model: "openai/gpt-3.5-turbo",
    tools: [cached_search_tool]
  )

stats = CachedSearchAPI.stats()
IO.puts("\nCache Statistics:")
IO.puts("  Cached queries: #{stats.cache_size}")
IO.puts("  Total API calls: #{stats.total_calls}")
IO.puts("  Cache hit rate: #{if stats.total_calls > 0, do: "50%", else: "N/A"}\n")

# ============================================================================
# Example 8: Production Integration Guide
# ============================================================================

IO.puts("8. Production Integration Guide\n")

IO.puts("Real Search API Integration:")
IO.puts("1. Google Custom Search:")
IO.puts("   - Sign up: https://developers.google.com/custom-search")
IO.puts("   - 100 free queries/day, $5/1000 queries after")
IO.puts("   - Use Req: Req.get!(url, params: [key: api_key, cx: cx, q: query])")

IO.puts("\n2. Brave Search API:")
IO.puts("   - Sign up: https://brave.com/search/api/")
IO.puts("   - 2000 free queries/month")
IO.puts("   - Good privacy-focused alternative")

IO.puts("\n3. Bing Search API:")
IO.puts("   - Azure Cognitive Services")
IO.puts("   - 1000 free transactions/month")
IO.puts("   - Comprehensive results")

IO.puts("\n4. DuckDuckGo (Free, Limited):")
IO.puts("   - Instant Answer API")
IO.puts("   - No API key required")
IO.puts("   - Limited functionality")

IO.puts("\nBest Practices:")
IO.puts("- Cache search results (ETS, Redis)")
IO.puts("- Rate limit API calls")
IO.puts("- Handle API errors gracefully")
IO.puts("- Log search queries for analysis")
IO.puts("- Use RunContext to track search history")
IO.puts("- Implement retry logic with backoff")
IO.puts("- Monitor API usage and costs")
IO.puts("- Consider using multiple search providers for redundancy")

IO.puts("")

IO.puts("=== Web Search Example Complete ===\n")
