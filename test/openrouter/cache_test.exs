defmodule Openrouter.CacheTest do
  use ExUnit.Case, async: true

  alias Openrouter.Cache

  describe "start_link/1" do
    test "starts with default options" do
      assert {:ok, cache} = Cache.start_link()
      assert Process.alive?(cache)
    end

    test "starts with map backend" do
      assert {:ok, cache} = Cache.start_link(backend: :map)
      assert Process.alive?(cache)
    end

    test "starts with ETS backend" do
      assert {:ok, cache} = Cache.start_link(backend: :ets)
      assert Process.alive?(cache)
    end

    test "starts with custom name" do
      assert {:ok, cache} = Cache.start_link(name: :test_cache)
      assert Process.whereis(:test_cache) == cache
    end

    test "starts with custom options" do
      assert {:ok, cache} =
               Cache.start_link(
                 max_size: 50,
                 eviction_policy: :fifo,
                 default_ttl: :timer.minutes(30)
               )

      assert Process.alive?(cache)
    end
  end

  describe "put/get with map backend" do
    setup do
      {:ok, cache} = Cache.start_link(backend: :map)
      {:ok, cache: cache}
    end

    test "stores and retrieves a value", %{cache: cache} do
      :ok = Cache.put(cache, "key1", "value1")

      assert {:ok, "value1"} = Cache.get(cache, "key1")
    end

    test "returns :miss for non-existent key", %{cache: cache} do
      assert :miss = Cache.get(cache, "nonexistent")
    end

    test "overwrites existing value", %{cache: cache} do
      Cache.put(cache, "key", "old")
      Cache.put(cache, "key", "new")

      assert {:ok, "new"} = Cache.get(cache, "key")
    end

    test "stores different types", %{cache: cache} do
      Cache.put(cache, "string", "hello")
      Cache.put(cache, "integer", 42)
      Cache.put(cache, "list", [1, 2, 3])
      Cache.put(cache, "map", %{a: 1, b: 2})

      assert {:ok, "hello"} = Cache.get(cache, "string")
      assert {:ok, 42} = Cache.get(cache, "integer")
      assert {:ok, [1, 2, 3]} = Cache.get(cache, "list")
      assert {:ok, %{a: 1, b: 2}} = Cache.get(cache, "map")
    end

    test "handles atom keys", %{cache: cache} do
      Cache.put(cache, :atom_key, "value")

      assert {:ok, "value"} = Cache.get(cache, :atom_key)
    end

    test "handles tuple keys", %{cache: cache} do
      Cache.put(cache, {:compound, "key"}, "value")

      assert {:ok, "value"} = Cache.get(cache, {:compound, "key"})
    end
  end

  describe "put/get with ETS backend" do
    setup do
      {:ok, cache} = Cache.start_link(backend: :ets)
      {:ok, cache: cache}
    end

    test "stores and retrieves with ETS", %{cache: cache} do
      Cache.put(cache, "key", "value")

      assert {:ok, "value"} = Cache.get(cache, "key")
    end

    test "handles concurrent access", %{cache: cache} do
      # ETS allows concurrent reads
      Cache.put(cache, "shared", "data")

      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            Cache.get(cache, "shared")
          end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, &(&1 == {:ok, "data"}))
    end
  end

  describe "TTL and expiration" do
    setup do
      {:ok, cache} = Cache.start_link()
      {:ok, cache: cache}
    end

    test "respects TTL", %{cache: cache} do
      Cache.put(cache, "temp", "value", ttl: 50)

      # Should exist immediately
      assert {:ok, "value"} = Cache.get(cache, "temp")

      # Wait for expiration
      Process.sleep(100)

      # Should be gone
      assert :miss = Cache.get(cache, "temp")
    end

    test "infinite TTL never expires", %{cache: cache} do
      Cache.put(cache, "permanent", "forever", ttl: :infinity)

      # Check immediately
      assert {:ok, "forever"} = Cache.get(cache, "permanent")

      # Check after some time
      Process.sleep(100)
      assert {:ok, "forever"} = Cache.get(cache, "permanent")
    end

    test "uses default TTL when not specified", %{cache: cache} do
      Cache.put(cache, "default", "value")

      assert {:ok, "value"} = Cache.get(cache, "default")
    end

    test "custom TTL overrides default", %{cache: cache} do
      Cache.put(cache, "custom", "value", ttl: :infinity)

      # Should not expire even if default TTL is short
      Process.sleep(50)
      assert {:ok, "value"} = Cache.get(cache, "custom")
    end
  end

  describe "fetch/3" do
    setup do
      {:ok, cache} = Cache.start_link()
      {:ok, cache: cache}
    end

    test "computes value on cache miss", %{cache: cache} do
      result =
        Cache.fetch(cache, "key", fn ->
          "computed"
        end)

      assert result == "computed"
      assert {:ok, "computed"} = Cache.get(cache, "key")
    end

    test "returns cached value on hit", %{cache: cache} do
      # Pre-populate
      Cache.put(cache, "key", "cached")

      # Fetch should return cached value without computing
      result =
        Cache.fetch(cache, "key", fn ->
          raise "Should not compute!"
        end)

      assert result == "cached"
    end

    test "caches computed result", %{cache: cache} do
      call_count = Agent.start_link(fn -> 0 end)
      {:ok, agent} = call_count

      compute_fn = fn ->
        Agent.update(agent, &(&1 + 1))
        "result"
      end

      # First call computes
      Cache.fetch(cache, "key", compute_fn)
      assert Agent.get(agent, & &1) == 1

      # Second call uses cache
      Cache.fetch(cache, "key", compute_fn)
      assert Agent.get(agent, & &1) == 1
    end

    test "respects force option", %{cache: cache} do
      Cache.put(cache, "key", "old")

      # Force recompute
      result = Cache.fetch(cache, "key", fn -> "new" end, force: true)

      assert result == "new"
      assert {:ok, "new"} = Cache.get(cache, "key")
    end

    test "accepts TTL option", %{cache: cache} do
      Cache.fetch(cache, "key", fn -> "value" end, ttl: :infinity)

      Process.sleep(100)
      assert {:ok, "value"} = Cache.get(cache, "key")
    end
  end

  describe "delete/2" do
    setup do
      {:ok, cache} = Cache.start_link()
      {:ok, cache: cache}
    end

    test "removes a key", %{cache: cache} do
      Cache.put(cache, "key", "value")
      assert {:ok, "value"} = Cache.get(cache, "key")

      :ok = Cache.delete(cache, "key")

      assert :miss = Cache.get(cache, "key")
    end

    test "delete non-existent key is safe", %{cache: cache} do
      assert :ok = Cache.delete(cache, "nonexistent")
    end

    test "deletes specific key only", %{cache: cache} do
      Cache.put(cache, "key1", "value1")
      Cache.put(cache, "key2", "value2")

      Cache.delete(cache, "key1")

      assert :miss = Cache.get(cache, "key1")
      assert {:ok, "value2"} = Cache.get(cache, "key2")
    end
  end

  describe "clear/1" do
    setup do
      {:ok, cache} = Cache.start_link()
      {:ok, cache: cache}
    end

    test "removes all entries", %{cache: cache} do
      Cache.put(cache, "key1", "value1")
      Cache.put(cache, "key2", "value2")
      Cache.put(cache, "key3", "value3")

      :ok = Cache.clear(cache)

      assert :miss = Cache.get(cache, "key1")
      assert :miss = Cache.get(cache, "key2")
      assert :miss = Cache.get(cache, "key3")
    end

    test "resets size to zero", %{cache: cache} do
      Cache.put(cache, "key1", "value1")
      Cache.put(cache, "key2", "value2")

      Cache.clear(cache)

      assert Cache.size(cache) == 0
    end

    test "resets statistics", %{cache: cache} do
      Cache.put(cache, "key", "value")
      # hit
      Cache.get(cache, "key")
      # miss
      Cache.get(cache, "other")

      Cache.clear(cache)

      stats = Cache.stats(cache)
      assert stats.hits == 0
      assert stats.misses == 0
    end
  end

  describe "size/1" do
    setup do
      {:ok, cache} = Cache.start_link()
      {:ok, cache: cache}
    end

    test "returns zero for empty cache", %{cache: cache} do
      assert Cache.size(cache) == 0
    end

    test "returns correct count", %{cache: cache} do
      Cache.put(cache, "key1", "value1")
      assert Cache.size(cache) == 1

      Cache.put(cache, "key2", "value2")
      assert Cache.size(cache) == 2

      Cache.put(cache, "key3", "value3")
      assert Cache.size(cache) == 3
    end

    test "decrements on delete", %{cache: cache} do
      Cache.put(cache, "key", "value")
      assert Cache.size(cache) == 1

      Cache.delete(cache, "key")
      assert Cache.size(cache) == 0
    end

    test "overwrites don't increase size", %{cache: cache} do
      Cache.put(cache, "key", "old")
      Cache.put(cache, "key", "new")

      assert Cache.size(cache) == 1
    end
  end

  describe "stats/1" do
    setup do
      {:ok, cache} = Cache.start_link()
      {:ok, cache: cache}
    end

    test "tracks hits and misses", %{cache: cache} do
      Cache.put(cache, "key", "value")

      # Hit
      Cache.get(cache, "key")
      # Miss
      Cache.get(cache, "other")

      stats = Cache.stats(cache)

      assert stats.hits == 1
      assert stats.misses == 1
    end

    test "calculates hit rate", %{cache: cache} do
      Cache.put(cache, "key", "value")

      # 3 hits
      Cache.get(cache, "key")
      Cache.get(cache, "key")
      Cache.get(cache, "key")

      # 1 miss
      Cache.get(cache, "other")

      stats = Cache.stats(cache)

      assert stats.hit_rate == 0.75
    end

    test "hit rate is 0 with no requests", %{cache: cache} do
      stats = Cache.stats(cache)

      assert stats.hit_rate == 0.0
    end

    test "includes size", %{cache: cache} do
      Cache.put(cache, "key1", "value1")
      Cache.put(cache, "key2", "value2")

      stats = Cache.stats(cache)

      assert stats.size == 2
    end

    test "includes memory estimate", %{cache: cache} do
      Cache.put(cache, "key", "value")

      stats = Cache.stats(cache)

      assert is_integer(stats.memory_bytes)
      assert stats.memory_bytes > 0
    end
  end

  describe "eviction with LRU policy" do
    setup do
      {:ok, cache} = Cache.start_link(max_size: 3, eviction_policy: :lru)
      {:ok, cache: cache}
    end

    test "evicts least recently used", %{cache: cache} do
      # Fill cache
      Cache.put(cache, "key1", "value1")
      Cache.put(cache, "key2", "value2")
      Cache.put(cache, "key3", "value3")

      # Access key1 and key2 (making key3 LRU)
      Cache.get(cache, "key1")
      Cache.get(cache, "key2")

      # Add new entry, should evict key3
      Cache.put(cache, "key4", "value4")

      assert {:ok, "value1"} = Cache.get(cache, "key1")
      assert {:ok, "value2"} = Cache.get(cache, "key2")
      assert :miss = Cache.get(cache, "key3")
      assert {:ok, "value4"} = Cache.get(cache, "key4")
    end

    test "tracks eviction count", %{cache: cache} do
      Cache.put(cache, "key1", "value1")
      Cache.put(cache, "key2", "value2")
      Cache.put(cache, "key3", "value3")
      # Evicts key1
      Cache.put(cache, "key4", "value4")

      stats = Cache.stats(cache)

      assert stats.evictions >= 1
    end

    test "maintains max size", %{cache: cache} do
      # Add more than max_size entries
      for i <- 1..10 do
        Cache.put(cache, "key#{i}", "value#{i}")
      end

      assert Cache.size(cache) <= 3
    end
  end

  describe "eviction with FIFO policy" do
    setup do
      {:ok, cache} = Cache.start_link(max_size: 3, eviction_policy: :fifo)
      {:ok, cache: cache}
    end

    test "evicts first in", %{cache: cache} do
      Cache.put(cache, "key1", "value1")
      Process.sleep(10)
      Cache.put(cache, "key2", "value2")
      Process.sleep(10)
      Cache.put(cache, "key3", "value3")

      # Access key1 multiple times (shouldn't matter for FIFO)
      Cache.get(cache, "key1")
      Cache.get(cache, "key1")

      Process.sleep(10)

      # Add new entry, should evict key1 (first inserted)
      Cache.put(cache, "key4", "value4")

      assert :miss = Cache.get(cache, "key1")
      assert {:ok, "value2"} = Cache.get(cache, "key2")
      assert {:ok, "value3"} = Cache.get(cache, "key3")
      assert {:ok, "value4"} = Cache.get(cache, "key4")
    end
  end

  describe "chat_key/2" do
    test "generates consistent keys" do
      messages = [%{role: "user", content: "Hello"}]

      key1 = Cache.chat_key(messages, model: "gpt-4")
      key2 = Cache.chat_key(messages, model: "gpt-4")

      assert key1 == key2
    end

    test "different messages produce different keys" do
      msg1 = [%{role: "user", content: "Hello"}]
      msg2 = [%{role: "user", content: "Goodbye"}]

      key1 = Cache.chat_key(msg1, model: "gpt-4")
      key2 = Cache.chat_key(msg2, model: "gpt-4")

      assert key1 != key2
    end

    test "different models produce different keys" do
      messages = [%{role: "user", content: "Hello"}]

      key1 = Cache.chat_key(messages, model: "gpt-4")
      key2 = Cache.chat_key(messages, model: "gpt-3.5-turbo")

      assert key1 != key2
    end

    test "temperature affects key for non-zero temps" do
      messages = [%{role: "user", content: "Hello"}]

      key1 = Cache.chat_key(messages, model: "gpt-4", temperature: 0.7)
      key2 = Cache.chat_key(messages, model: "gpt-4", temperature: 0.9)

      assert key1 != key2
    end

    test "deterministic (temp=0) uses simpler key" do
      messages = [%{role: "user", content: "Hello"}]

      key = Cache.chat_key(messages, model: "gpt-4", temperature: 0)

      # Deterministic key should not include temperature in format
      assert key =~ "chat:gpt-4:"
      refute key =~ ":t0:"
    end

    test "includes model in key" do
      messages = [%{role: "user", content: "Hello"}]

      key = Cache.chat_key(messages, model: "my-model")

      assert key =~ "my-model"
    end
  end

  describe "embedding_key/2" do
    test "generates consistent keys" do
      key1 = Cache.embedding_key("hello world", model: "ada")
      key2 = Cache.embedding_key("hello world", model: "ada")

      assert key1 == key2
    end

    test "different text produces different keys" do
      key1 = Cache.embedding_key("hello", model: "ada")
      key2 = Cache.embedding_key("world", model: "ada")

      assert key1 != key2
    end

    test "different models produce different keys" do
      key1 = Cache.embedding_key("hello", model: "ada-002")
      key2 = Cache.embedding_key("hello", model: "ada-003")

      assert key1 != key2
    end

    test "handles list input" do
      key1 = Cache.embedding_key(["hello", "world"], model: "ada")
      key2 = Cache.embedding_key(["hello", "world"], model: "ada")

      assert key1 == key2
    end

    test "list vs string produces different keys" do
      key1 = Cache.embedding_key("hello", model: "ada")
      key2 = Cache.embedding_key(["hello"], model: "ada")

      assert key1 != key2
    end

    test "includes model in key" do
      key = Cache.embedding_key("test", model: "my-model")

      assert key =~ "my-model"
    end

    test "starts with embedding prefix" do
      key = Cache.embedding_key("test", model: "ada")

      assert String.starts_with?(key, "embedding:")
    end
  end

  describe "fetch_embedding/3" do
    setup do
      {:ok, cache} = Cache.start_link()
      {:ok, cache: cache}
    end

    test "computes embedding on first call", %{cache: cache} do
      call_count = Agent.start_link(fn -> 0 end)
      {:ok, agent} = call_count

      compute_fn = fn ->
        Agent.update(agent, &(&1 + 1))
        %{embedding: [0.1, 0.2, 0.3]}
      end

      result = Cache.fetch_embedding(cache, "hello", compute_fn: compute_fn)

      assert result == %{embedding: [0.1, 0.2, 0.3]}
      assert Agent.get(agent, & &1) == 1
    end

    test "uses cache on second call", %{cache: cache} do
      call_count = Agent.start_link(fn -> 0 end)
      {:ok, agent} = call_count

      compute_fn = fn ->
        Agent.update(agent, &(&1 + 1))
        %{embedding: [0.1, 0.2, 0.3]}
      end

      # First call
      Cache.fetch_embedding(cache, "hello", compute_fn: compute_fn)

      # Second call should use cache
      result = Cache.fetch_embedding(cache, "hello", compute_fn: compute_fn)

      assert result == %{embedding: [0.1, 0.2, 0.3]}
      # Only called once
      assert Agent.get(agent, & &1) == 1
    end

    test "uses infinite TTL by default", %{cache: cache} do
      Cache.fetch_embedding(cache, "hello", compute_fn: fn -> %{embedding: [1, 2, 3]} end)

      # Should still be cached after delay
      Process.sleep(100)

      result =
        Cache.fetch_embedding(cache, "hello", compute_fn: fn -> raise "Should not compute!" end)

      assert result == %{embedding: [1, 2, 3]}
    end

    test "accepts custom TTL", %{cache: cache} do
      Cache.fetch_embedding(cache, "temp",
        compute_fn: fn -> %{embedding: [1]} end,
        ttl: 50
      )

      # Wait for expiration
      Process.sleep(100)

      # Should recompute
      result =
        Cache.fetch_embedding(cache, "temp",
          compute_fn: fn -> %{embedding: [2]} end,
          ttl: 50
        )

      assert result == %{embedding: [2]}
    end
  end

  describe "access count tracking" do
    setup do
      {:ok, cache} = Cache.start_link()
      {:ok, cache: cache}
    end

    test "tracks access count", %{cache: cache} do
      Cache.put(cache, "key", "value")

      # Access multiple times
      Cache.get(cache, "key")
      Cache.get(cache, "key")
      Cache.get(cache, "key")

      stats = Cache.stats(cache)
      assert stats.hits == 3
    end
  end
end
