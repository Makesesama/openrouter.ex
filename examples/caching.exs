# Caching Examples for Openrouter.ex
#
# This file demonstrates how to use caching to reduce API costs and latency
# by avoiding redundant LLM calls for identical or similar requests.
#
# To run these examples:
#   export OPENROUTER_API_KEY="or-..."
#   mix run examples/caching.exs

alias Openrouter.Cache

IO.puts("\n=== Example 1: Basic Cache Operations ===")

# Start a cache server
{:ok, cache} = Cache.start_link(backend: :map, name: :demo_cache)

# Store a value
Cache.put(cache, "greeting", "Hello, World!", ttl: :timer.minutes(5))

# Retrieve it
case Cache.get(cache, "greeting") do
  {:ok, value} ->
    IO.puts("✓ Cache hit: #{value}")
  :miss ->
    IO.puts("✗ Cache miss")
end

# Try a non-existent key
case Cache.get(cache, "nonexistent") do
  {:ok, value} ->
    IO.puts("Found: #{value}")
  :miss ->
    IO.puts("✓ Cache miss for nonexistent key (expected)")
end

IO.puts("\n=== Example 2: Caching Chat Completions ===")

messages = [
  %{role: "user", content: "What is 2+2?"}
]

# Generate cache key
cache_key = Cache.chat_key(messages, model: "openai/gpt-3.5-turbo", temperature: 0)
IO.puts("Cache key: #{cache_key}")

# Fetch with automatic caching
IO.puts("\nFirst call (cache miss, will hit API):")
start_time = System.monotonic_time(:millisecond)

result1 = Cache.fetch(cache, cache_key, fn ->
  IO.puts("  → Calling OpenRouter API...")
  case Openrouter.chat(messages, model: "openai/gpt-3.5-turbo", temperature: 0) do
    {:ok, response} -> response
    {:error, error} ->
      IO.puts("  Error: #{inspect(error)}")
      nil
  end
end, ttl: :timer.hours(24))

elapsed1 = System.monotonic_time(:millisecond) - start_time
IO.puts("  Time: #{elapsed1}ms")

if result1 do
  answer = result1.choices |> List.first() |> Map.get(:message) |> Map.get(:content)
  IO.puts("  Answer: #{answer}")
end

# Second identical request (should be cached)
IO.puts("\nSecond call (cache hit, instant):")
start_time2 = System.monotonic_time(:millisecond)

result2 = Cache.fetch(cache, cache_key, fn ->
  IO.puts("  → This should not print (cache hit)")
  Openrouter.chat(messages, model: "openai/gpt-3.5-turbo", temperature: 0)
end, ttl: :timer.hours(24))

elapsed2 = System.monotonic_time(:millisecond) - start_time2
IO.puts("  Time: #{elapsed2}ms (#{div(elapsed1, max(elapsed2, 1))}x faster)")

IO.puts("\n=== Example 3: Cache Statistics ===")

# Make several requests to build up statistics
Cache.fetch(cache, "key1", fn -> "value1" end)
Cache.fetch(cache, "key2", fn -> "value2" end)
Cache.fetch(cache, "key1", fn -> "should not compute" end)  # Hit
Cache.fetch(cache, "key3", fn -> "value3" end)
Cache.fetch(cache, "key2", fn -> "should not compute" end)  # Hit

stats = Cache.stats(cache)
IO.puts("Cache Statistics:")
IO.puts("  Total requests: #{stats.hits + stats.misses}")
IO.puts("  Hits: #{stats.hits}")
IO.puts("  Misses: #{stats.misses}")
IO.puts("  Hit rate: #{Float.round(stats.hit_rate * 100, 1)}%")
IO.puts("  Cache size: #{stats.size} entries")
IO.puts("  Memory: #{div(stats.memory_bytes, 1024)} KB")

IO.puts("\n=== Example 4: TTL and Expiration ===")

# Cache with short TTL
Cache.put(cache, "ephemeral", "This will expire soon", ttl: 100)

# Immediate retrieval works
{:ok, _} = Cache.get(cache, "ephemeral")
IO.puts("✓ Retrieved before expiration")

# Wait for expiration
IO.puts("Waiting 150ms for expiration...")
Process.sleep(150)

# Now it should be expired
case Cache.get(cache, "ephemeral") do
  {:ok, _} -> IO.puts("✗ Unexpectedly found (TTL didn't work)")
  :miss -> IO.puts("✓ Expired as expected")
end

# Infinite TTL
Cache.put(cache, "permanent", "This never expires", ttl: :infinity)
IO.puts("✓ Stored with infinite TTL")

IO.puts("\n=== Example 5: Embedding Caching ===")

# Embeddings are deterministic, so cache them forever
embedding_text = "Machine learning is a subset of artificial intelligence"

embedding_key = Cache.embedding_key(embedding_text, model: "text-embedding-ada-002")
IO.puts("Embedding cache key: #{String.slice(embedding_key, 0, 50)}...")

# Simulate embedding fetch (replace with real API call)
embedding_result = Cache.fetch_embedding(cache, embedding_text,
  model: "text-embedding-ada-002",
  ttl: :infinity,
  compute_fn: fn ->
    IO.puts("  → Computing embedding (cache miss)...")
    # In real usage: Openrouter.embeddings(embedding_text, model: "...")
    %{embedding: [0.1, 0.2, 0.3], model: "text-embedding-ada-002"}
  end
)

IO.puts("✓ Embedding cached: #{inspect(embedding_result)}")

# Second fetch is instant
embedding_result2 = Cache.fetch_embedding(cache, embedding_text,
  model: "text-embedding-ada-002",
  compute_fn: fn ->
    IO.puts("  → This should not print")
    raise "Should use cache!"
  end
)

IO.puts("✓ Retrieved from cache (instant)")

IO.puts("\n=== Example 6: ETS Backend (Cross-Process) ===")

# Start cache with ETS backend
{:ok, ets_cache} = Cache.start_link(backend: :ets, name: :ets_cache)

# Store data
Cache.put(ets_cache, "shared_data", "Accessible across processes")

# ETS allows cross-process access
spawn(fn ->
  case Cache.get(ets_cache, "shared_data") do
    {:ok, value} ->
      IO.puts("✓ Process #{inspect(self())} accessed: #{value}")
    :miss ->
      IO.puts("✗ Could not access from other process")
  end
end)

# Wait for spawned process
Process.sleep(100)

IO.puts("\n=== Example 7: Cache Eviction (LRU) ===")

# Create small cache to demonstrate eviction
{:ok, small_cache} = Cache.start_link(
  backend: :map,
  max_size: 3,
  eviction_policy: :lru
)

IO.puts("Cache max size: 3 entries")

# Fill cache
Cache.put(small_cache, "key1", "value1")
Cache.put(small_cache, "key2", "value2")
Cache.put(small_cache, "key3", "value3")
IO.puts("Inserted 3 entries: key1, key2, key3")
IO.puts("Cache size: #{Cache.size(small_cache)}")

# Access key1 and key2 (updates last_accessed)
Cache.get(small_cache, "key1")
Cache.get(small_cache, "key2")
IO.puts("Accessed key1 and key2 (making key3 least recently used)")

# Insert new entry, should evict key3 (LRU)
Cache.put(small_cache, "key4", "value4")
IO.puts("Inserted key4 (should evict key3)")

# Check what's in cache
IO.puts("\nChecking cache contents:")
for key <- ["key1", "key2", "key3", "key4"] do
  case Cache.get(small_cache, key) do
    {:ok, _} -> IO.puts("  ✓ #{key} present")
    :miss -> IO.puts("  ✗ #{key} evicted")
  end
end

stats = Cache.stats(small_cache)
IO.puts("\nEvictions: #{stats.evictions}")

IO.puts("\n=== Example 8: Temperature-Based Caching ===")

# Deterministic responses (temp=0) should be cached
deterministic_key = Cache.chat_key(
  [%{role: "user", content: "Count to 5"}],
  model: "gpt-4",
  temperature: 0
)

# Non-deterministic responses need different cache strategy
random_key = Cache.chat_key(
  [%{role: "user", content: "Count to 5"}],
  model: "gpt-4",
  temperature: 0.9
)

IO.puts("Same message, different temperatures:")
IO.puts("  Temp=0 key: #{String.slice(deterministic_key, 0, 40)}...")
IO.puts("  Temp=0.9 key: #{String.slice(random_key, 0, 40)}...")
IO.puts("  Keys are different: #{deterministic_key != random_key}")

IO.puts("\n=== Example 9: Cache Management ===")

{:ok, mgmt_cache} = Cache.start_link()

# Add some entries
Cache.put(mgmt_cache, "a", 1)
Cache.put(mgmt_cache, "b", 2)
Cache.put(mgmt_cache, "c", 3)

IO.puts("Cache size before clear: #{Cache.size(mgmt_cache)}")

# Clear cache
Cache.clear(mgmt_cache)
IO.puts("Cache size after clear: #{Cache.size(mgmt_cache)}")

# Verify empty
case Cache.get(mgmt_cache, "a") do
  :miss -> IO.puts("✓ Cache successfully cleared")
  {:ok, _} -> IO.puts("✗ Cache not cleared")
end

# Delete specific key
Cache.put(mgmt_cache, "x", 10)
Cache.put(mgmt_cache, "y", 20)

Cache.delete(mgmt_cache, "x")
IO.puts("\nAfter deleting 'x':")
IO.puts("  x present: #{match?({:ok, _}, Cache.get(mgmt_cache, "x"))}")
IO.puts("  y present: #{match?({:ok, _}, Cache.get(mgmt_cache, "y"))}")

IO.puts("\n=== Example 10: Production RAG with Caching ===")

# Simulate a RAG system with cached embeddings and responses
defmodule RAGExample do
  def search_documents(query, cache) do
    # Cache the query embedding
    query_embedding = Openrouter.Cache.fetch_embedding(cache, query,
      model: "text-embedding-ada-002",
      ttl: :infinity,
      compute_fn: fn ->
        IO.puts("  Computing query embedding...")
        # Simulate embedding
        %{embedding: :rand.uniform() |> List.duplicate(1536)}
      end
    )

    IO.puts("✓ Query embedding ready")

    # Cache the search results
    search_key = "search:#{:crypto.hash(:sha256, query) |> Base.encode16()}"

    results = Openrouter.Cache.fetch(cache, search_key, fn ->
      IO.puts("  Searching document database...")
      # Simulate document search
      Process.sleep(50)
      ["Doc1: About AI", "Doc2: About ML", "Doc3: About DL"]
    end, ttl: :timer.minutes(30))

    IO.puts("✓ Search results: #{length(results)} documents")

    # Cache the final LLM response
    llm_key = Openrouter.Cache.chat_key(
      [%{role: "user", content: "Answer based on: #{inspect(results)} Question: #{query}"}],
      model: "gpt-4",
      temperature: 0
    )

    answer = Openrouter.Cache.fetch(cache, llm_key, fn ->
      IO.puts("  Generating answer with LLM...")
      # Simulate LLM call
      "Based on the documents, here's the answer..."
    end, ttl: :timer.hours(24))

    IO.puts("✓ Answer generated")
    answer
  end
end

{:ok, rag_cache} = Cache.start_link(name: :rag_cache, max_size: 500)

IO.puts("First query (all cache misses):")
RAGExample.search_documents("What is machine learning?", rag_cache)

IO.puts("\nSecond identical query (all cache hits):")
RAGExample.search_documents("What is machine learning?", rag_cache)

stats = Cache.stats(rag_cache)
IO.puts("\nRAG Cache Performance:")
IO.puts("  Hit rate: #{Float.round(stats.hit_rate * 100, 1)}%")
IO.puts("  Total entries: #{stats.size}")

IO.puts("\n=== All Examples Complete ===")
