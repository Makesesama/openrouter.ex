defmodule Openrouter.Cache do
  @moduledoc """
  Response and embedding caching to reduce API costs and latency.

  This module provides flexible caching for LLM responses and embeddings with
  multiple backend options, TTL support, and cache statistics.

  ## Features

  - In-memory caching with TTL (time-to-live)
  - ETS-based caching for cross-process persistence
  - Automatic cache key generation based on request parameters
  - Cache statistics (hits, misses, size)
  - Configurable eviction policies
  - Support for different cache backends

  ## Usage

  ### Basic In-Memory Caching

      # Start cache server
      {:ok, cache} = Openrouter.Cache.start_link(backend: :ets, name: :my_cache)

      # Cache a response
      cache_key = "chat:model:prompt_hash"
      response = %{content: "...", usage: %{...}}

      Openrouter.Cache.put(cache, cache_key, response, ttl: :timer.hours(1))

      # Retrieve from cache
      case Openrouter.Cache.get(cache, cache_key) do
        {:ok, cached_response} ->
          IO.puts("Cache hit!")
          cached_response
        :miss ->
          IO.puts("Cache miss, calling API...")
          # Make API call...
      end

  ### Automatic Caching Wrapper

      # Cache a chat completion
      result = Openrouter.Cache.fetch(cache, ["messages", model: "gpt-4"], fn ->
        Openrouter.chat(messages, model: "gpt-4")
      end, ttl: :timer.hours(24))

  ### Embedding Caching

      # Embeddings are deterministic, so cache them indefinitely
      embedding = Openrouter.Cache.fetch_embedding(cache, "text to embed",
        model: "text-embedding-ada-002",
        ttl: :infinity
      )

  ### Cache Statistics

      stats = Openrouter.Cache.stats(cache)
      # => %{hits: 42, misses: 8, hit_rate: 0.84, size: 50, memory_bytes: 12480}

  ## Configuration

  You can configure default cache settings in config.exs:

      config :openrouter,
        cache: [
          backend: :ets,
          default_ttl: :timer.hours(1),
          max_size: 1000,
          eviction_policy: :lru
        ]
  """

  use GenServer
  require Logger

  @type cache_key :: String.t() | term()
  @type ttl :: pos_integer() | :infinity
  @type backend :: :ets | :map | :none
  @type cache_entry :: %{
          value: term(),
          inserted_at: integer(),
          ttl: ttl(),
          access_count: non_neg_integer(),
          last_accessed: integer()
        }

  defstruct backend: :map,
            storage: nil,
            stats: %{hits: 0, misses: 0, evictions: 0},
            max_size: 1000,
            eviction_policy: :lru,
            default_ttl: :timer.hours(1)

  ## Client API

  @doc """
  Starts a new cache process.

  ## Options

  - `:backend` - Cache backend (`:ets`, `:map`). Default: `:map`
  - `:name` - Optional registered name
  - `:max_size` - Maximum cache entries. Default: 1000
  - `:eviction_policy` - `:lru` (least recently used) or `:fifo`. Default: `:lru`
  - `:default_ttl` - Default TTL in milliseconds. Default: 1 hour

  ## Examples

      {:ok, cache} = Cache.start_link(backend: :ets, name: :my_cache)
      {:ok, cache} = Cache.start_link(max_size: 500, default_ttl: :timer.minutes(30))
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Retrieves a value from the cache.

  Returns `{:ok, value}` if found and not expired, `:miss` otherwise.

  ## Examples

      case Cache.get(cache, "my_key") do
        {:ok, value} -> IO.puts("Hit: #{inspect(value)}")
        :miss -> IO.puts("Miss")
      end
  """
  @spec get(GenServer.server(), cache_key()) :: {:ok, term()} | :miss
  def get(server, key) do
    GenServer.call(server, {:get, key})
  end

  @doc """
  Stores a value in the cache with optional TTL.

  ## Options

  - `:ttl` - Time-to-live in milliseconds, or `:infinity`. Default: cache's default_ttl

  ## Examples

      Cache.put(cache, "key", "value", ttl: :timer.hours(2))
      Cache.put(cache, "permanent", data, ttl: :infinity)
  """
  @spec put(GenServer.server(), cache_key(), term(), keyword()) :: :ok
  def put(server, key, value, opts \\ []) do
    GenServer.call(server, {:put, key, value, opts})
  end

  @doc """
  Fetches a value from cache or computes it using the provided function.

  If the key exists in cache and is not expired, returns the cached value.
  Otherwise, executes the function, caches the result, and returns it.

  ## Options

  - `:ttl` - Time-to-live for cached result. Default: cache's default_ttl
  - `:force` - If true, bypass cache and recompute. Default: false

  ## Examples

      result = Cache.fetch(cache, "expensive_computation", fn ->
        # This only runs on cache miss
        perform_expensive_operation()
      end, ttl: :timer.hours(24))
  """
  @spec fetch(GenServer.server(), cache_key(), (-> term()), keyword()) :: term()
  def fetch(server, key, compute_fn, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    if force do
      result = compute_fn.()
      put(server, key, result, opts)
      result
    else
      case get(server, key) do
        {:ok, value} ->
          value

        :miss ->
          result = compute_fn.()
          put(server, key, result, opts)
          result
      end
    end
  end

  @doc """
  Generates a cache key for a chat completion request.

  Creates a deterministic key based on messages, model, and parameters.

  ## Examples

      key = Cache.chat_key(messages, model: "gpt-4", temperature: 0.7)
  """
  @spec chat_key(list(), keyword()) :: String.t()
  def chat_key(messages, opts \\ []) do
    model = Keyword.get(opts, :model, "default")
    temperature = Keyword.get(opts, :temperature, 1.0)
    max_tokens = Keyword.get(opts, :max_tokens)

    # For deterministic responses (temp=0), include fewer params in key
    if temperature == 0 do
      content_hash = :crypto.hash(:sha256, :erlang.term_to_binary(messages)) |> Base.encode16()
      "chat:#{model}:#{content_hash}"
    else
      # For non-deterministic, include temperature and other params
      params = %{
        messages: messages,
        model: model,
        temperature: temperature,
        max_tokens: max_tokens
      }
      hash = :crypto.hash(:sha256, :erlang.term_to_binary(params)) |> Base.encode16()
      "chat:#{model}:t#{temperature}:#{hash}"
    end
  end

  @doc """
  Generates a cache key for an embedding request.

  Embeddings are deterministic, so the key is based on text and model only.

  ## Examples

      key = Cache.embedding_key("text to embed", model: "text-embedding-ada-002")
  """
  @spec embedding_key(String.t() | [String.t()], keyword()) :: String.t()
  def embedding_key(input, opts \\ []) do
    model = Keyword.get(opts, :model, "default")
    hash = :crypto.hash(:sha256, :erlang.term_to_binary(input)) |> Base.encode16()
    "embedding:#{model}:#{hash}"
  end

  @doc """
  Fetches an embedding from cache or computes it.

  Convenience wrapper for caching embeddings. Embeddings are deterministic,
  so they're cached with infinite TTL by default.

  ## Examples

      embedding = Cache.fetch_embedding(cache, "hello world",
        model: "text-embedding-ada-002",
        compute_fn: fn -> Openrouter.embeddings("hello world", model: "...") end
      )
  """
  @spec fetch_embedding(GenServer.server(), String.t() | [String.t()], keyword()) :: term()
  def fetch_embedding(server, input, opts \\ []) do
    compute_fn = Keyword.fetch!(opts, :compute_fn)
    ttl = Keyword.get(opts, :ttl, :infinity)

    key = embedding_key(input, opts)
    fetch(server, key, compute_fn, ttl: ttl)
  end

  @doc """
  Deletes a key from the cache.

  ## Examples

      Cache.delete(cache, "old_key")
  """
  @spec delete(GenServer.server(), cache_key()) :: :ok
  def delete(server, key) do
    GenServer.call(server, {:delete, key})
  end

  @doc """
  Clears all entries from the cache.

  ## Examples

      Cache.clear(cache)
  """
  @spec clear(GenServer.server()) :: :ok
  def clear(server) do
    GenServer.call(server, :clear)
  end

  @doc """
  Returns cache statistics.

  ## Examples

      stats = Cache.stats(cache)
      # => %{hits: 150, misses: 50, hit_rate: 0.75, size: 120, memory_bytes: 45600}
  """
  @spec stats(GenServer.server()) :: map()
  def stats(server) do
    GenServer.call(server, :stats)
  end

  @doc """
  Returns the current size (number of entries) in the cache.

  ## Examples

      size = Cache.size(cache)  # => 42
  """
  @spec size(GenServer.server()) :: non_neg_integer()
  def size(server) do
    GenServer.call(server, :size)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    backend = Keyword.get(opts, :backend, :map)
    max_size = Keyword.get(opts, :max_size, 1000)
    eviction_policy = Keyword.get(opts, :eviction_policy, :lru)
    default_ttl = Keyword.get(opts, :default_ttl, :timer.hours(1))

    storage = initialize_storage(backend)

    state = %__MODULE__{
      backend: backend,
      storage: storage,
      max_size: max_size,
      eviction_policy: eviction_policy,
      default_ttl: default_ttl
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case fetch_from_storage(state.storage, key, state.backend) do
      nil ->
        new_stats = update_stats(state.stats, :miss)
        {:reply, :miss, %{state | stats: new_stats}}

      entry ->
        if expired?(entry, now) do
          # Entry expired, remove it
          new_storage = delete_from_storage(state.storage, key, state.backend)
          new_stats = update_stats(state.stats, :miss)
          {:reply, :miss, %{state | storage: new_storage, stats: new_stats}}
        else
          # Valid entry, update access stats
          updated_entry = %{entry |
            access_count: entry.access_count + 1,
            last_accessed: now
          }
          new_storage = store_in_storage(state.storage, key, updated_entry, state.backend)
          new_stats = update_stats(state.stats, :hit)
          {:reply, {:ok, entry.value}, %{state | storage: new_storage, stats: new_stats}}
        end
    end
  end

  @impl true
  def handle_call({:put, key, value, opts}, _from, state) do
    ttl = Keyword.get(opts, :ttl, state.default_ttl)
    now = System.monotonic_time(:millisecond)

    entry = %{
      value: value,
      inserted_at: now,
      ttl: ttl,
      access_count: 0,
      last_accessed: now
    }

    # Check if we need to evict
    current_size = storage_size(state.storage, state.backend)
    {new_storage, new_stats} = if current_size >= state.max_size do
      # Evict based on policy
      evict_one(state.storage, state.backend, state.eviction_policy, state.stats)
    else
      {state.storage, state.stats}
    end

    final_storage = store_in_storage(new_storage, key, entry, state.backend)

    {:reply, :ok, %{state | storage: final_storage, stats: new_stats}}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    new_storage = delete_from_storage(state.storage, key, state.backend)
    {:reply, :ok, %{state | storage: new_storage}}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    new_storage = clear_storage(state.storage, state.backend)
    new_stats = %{hits: 0, misses: 0, evictions: 0}
    {:reply, :ok, %{state | storage: new_storage, stats: new_stats}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total_requests = state.stats.hits + state.stats.misses
    hit_rate = if total_requests > 0 do
      state.stats.hits / total_requests
    else
      0.0
    end

    size = storage_size(state.storage, state.backend)
    memory = estimate_memory(state.storage, state.backend)

    stats = Map.merge(state.stats, %{
      hit_rate: hit_rate,
      size: size,
      memory_bytes: memory
    })

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:size, _from, state) do
    size = storage_size(state.storage, state.backend)
    {:reply, size, state}
  end

  ## Private Helpers

  defp initialize_storage(:ets) do
    :ets.new(:cache, [:set, :private])
  end

  defp initialize_storage(:map) do
    %{}
  end

  defp fetch_from_storage(ets_table, key, :ets) when is_reference(ets_table) do
    case :ets.lookup(ets_table, key) do
      [{^key, entry}] -> entry
      [] -> nil
    end
  end

  defp fetch_from_storage(map, key, :map) when is_map(map) do
    Map.get(map, key)
  end

  defp store_in_storage(ets_table, key, entry, :ets) when is_reference(ets_table) do
    :ets.insert(ets_table, {key, entry})
    ets_table
  end

  defp store_in_storage(map, key, entry, :map) when is_map(map) do
    Map.put(map, key, entry)
  end

  defp delete_from_storage(ets_table, key, :ets) when is_reference(ets_table) do
    :ets.delete(ets_table, key)
    ets_table
  end

  defp delete_from_storage(map, key, :map) when is_map(map) do
    Map.delete(map, key)
  end

  defp clear_storage(ets_table, :ets) when is_reference(ets_table) do
    :ets.delete_all_objects(ets_table)
    ets_table
  end

  defp clear_storage(_map, :map) do
    %{}
  end

  defp storage_size(ets_table, :ets) when is_reference(ets_table) do
    :ets.info(ets_table, :size)
  end

  defp storage_size(map, :map) when is_map(map) do
    map_size(map)
  end

  defp estimate_memory(ets_table, :ets) when is_reference(ets_table) do
    :ets.info(ets_table, :memory) * :erlang.system_info(:wordsize)
  end

  defp estimate_memory(map, :map) when is_map(map) do
    # Rough estimate for map memory usage
    byte_size(:erlang.term_to_binary(map))
  end

  defp expired?(%{ttl: :infinity}, _now), do: false
  defp expired?(%{inserted_at: inserted_at, ttl: ttl}, now) do
    now > inserted_at + ttl
  end

  defp update_stats(stats, :hit) do
    Map.update(stats, :hits, 1, &(&1 + 1))
  end

  defp update_stats(stats, :miss) do
    Map.update(stats, :misses, 1, &(&1 + 1))
  end

  defp update_stats(stats, :eviction) do
    Map.update(stats, :evictions, 1, &(&1 + 1))
  end

  defp evict_one(ets_table, :ets, :lru, stats) do
    # Find entry with oldest last_accessed time
    victim = :ets.foldl(fn {key, entry}, acc ->
      case acc do
        nil -> {key, entry}
        {_acc_key, acc_entry} ->
          if entry.last_accessed < acc_entry.last_accessed do
            {key, entry}
          else
            acc
          end
      end
    end, nil, ets_table)

    case victim do
      {key, _entry} ->
        :ets.delete(ets_table, key)
        {ets_table, update_stats(stats, :eviction)}
      nil ->
        {ets_table, stats}
    end
  end

  defp evict_one(map, :map, :lru, stats) when is_map(map) do
    # Find entry with oldest last_accessed time
    victim = Enum.min_by(map, fn {_key, entry} -> entry.last_accessed end, fn -> nil end)

    case victim do
      {key, _entry} ->
        {Map.delete(map, key), update_stats(stats, :eviction)}
      nil ->
        {map, stats}
    end
  end

  defp evict_one(storage, backend, :fifo, stats) do
    # For FIFO, find oldest inserted_at
    evict_by_field(storage, backend, :inserted_at, stats)
  end

  defp evict_by_field(ets_table, :ets, field, stats) do
    victim = :ets.foldl(fn {key, entry}, acc ->
      case acc do
        nil -> {key, entry}
        {_acc_key, acc_entry} ->
          if Map.get(entry, field) < Map.get(acc_entry, field) do
            {key, entry}
          else
            acc
          end
      end
    end, nil, ets_table)

    case victim do
      {key, _entry} ->
        :ets.delete(ets_table, key)
        {ets_table, update_stats(stats, :eviction)}
      nil ->
        {ets_table, stats}
    end
  end

  defp evict_by_field(map, :map, field, stats) when is_map(map) do
    victim = Enum.min_by(map, fn {_key, entry} -> Map.get(entry, field) end, fn -> nil end)

    case victim do
      {key, _entry} ->
        {Map.delete(map, key), update_stats(stats, :eviction)}
      nil ->
        {map, stats}
    end
  end
end
