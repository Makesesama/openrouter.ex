#!/usr/bin/env elixir
#
# RAG (Retrieval Augmented Generation) Example
#
# This example demonstrates a complete RAG pipeline:
# - Document embedding
# - Vector similarity search
# - Context injection
# - Question answering with retrieved context
#
# Run with: mix run examples/rag.exs

Mix.install([{:openrouter, path: "."}])

require Logger

IO.puts("\n=== RAG (Retrieval Augmented Generation) Example ===\n")

# ============================================================================
# Example 1: Simple In-Memory Vector Store
# ============================================================================

defmodule SimpleVectorStore do
  @moduledoc """
  A simple in-memory vector store for demonstration purposes.
  In production, use a proper vector database like Qdrant, Pinecone, or pgvector.
  """

  defstruct [:documents, :embeddings]

  @doc """
  Creates a new vector store and indexes documents
  """
  def new(documents) do
    IO.puts("Indexing #{length(documents)} documents...")

    # Generate embeddings for all documents
    {:ok, embeddings} =
      Openrouter.embed(
        Enum.map(documents, & &1.content),
        model: "openai/text-embedding-3-small"
      )

    indexed_docs =
      Enum.zip([documents, embeddings])
      |> Enum.with_index()
      |> Enum.map(fn {{doc, embedding}, idx} ->
        %{
          id: idx,
          content: doc.content,
          metadata: doc.metadata,
          embedding: embedding
        }
      end)

    IO.puts("✓ Indexed #{length(indexed_docs)} documents\n")

    %__MODULE__{
      documents: indexed_docs,
      embeddings: embeddings
    }
  end

  @doc """
  Search for documents similar to query
  """
  def search(store, query, limit \\ 3) do
    # Get query embedding
    {:ok, [query_embedding]} =
      Openrouter.embed(query, model: "openai/text-embedding-3-small")

    # Calculate similarities and sort
    store.documents
    |> Enum.map(fn doc ->
      similarity = Openrouter.embed_similarity(query_embedding, doc.embedding)
      {doc, similarity}
    end)
    |> Enum.sort_by(fn {_doc, similarity} -> similarity end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {doc, similarity} -> Map.put(doc, :similarity, similarity) end)
  end
end

# ============================================================================
# Example 2: Basic RAG Pipeline
# ============================================================================

IO.puts("1. Basic RAG Pipeline")
IO.puts("   Embedding documents and answering questions\n")

# Sample knowledge base
documents = [
  %{
    content:
      "Elixir is a functional, concurrent programming language that runs on the Erlang VM (BEAM). It was created by José Valim in 2011.",
    metadata: %{source: "elixir_intro.txt", topic: "language"}
  },
  %{
    content:
      "Phoenix is a web framework written in Elixir. It provides real-time features through Phoenix Channels and LiveView.",
    metadata: %{source: "phoenix_intro.txt", topic: "framework"}
  },
  %{
    content:
      "OTP (Open Telecom Platform) is a set of Erlang libraries that provide tools for building robust, fault-tolerant applications. It includes supervisors, GenServers, and more.",
    metadata: %{source: "otp_intro.txt", topic: "infrastructure"}
  },
  %{
    content:
      "Ecto is the database wrapper and query generator for Elixir. It provides a DSL for writing queries and managing schemas.",
    metadata: %{source: "ecto_intro.txt", topic: "database"}
  },
  %{
    content:
      "The BEAM VM provides lightweight processes, fault tolerance, and hot code reloading. Millions of processes can run concurrently.",
    metadata: %{source: "beam_vm.txt", topic: "vm"}
  }
]

# Create vector store
store = SimpleVectorStore.new(documents)

# Query the knowledge base
query = "What is Phoenix and what features does it provide?"
IO.puts("Query: #{query}")

# Retrieve relevant documents
results = SimpleVectorStore.search(store, query, 2)

IO.puts("\nTop results:")

Enum.each(results, fn result ->
  IO.puts("  [#{Float.round(result.similarity, 3)}] #{String.slice(result.content, 0..80)}...")
end)

# Build context from retrieved documents
context =
  results
  |> Enum.map(& &1.content)
  |> Enum.join("\n\n")

# Ask LLM with context
system_prompt = """
You are a helpful assistant. Answer questions based on the provided context.
If the answer is not in the context, say so.

Context:
#{context}
"""

{:ok, response} =
  Openrouter.chat(
    [
      %{role: :system, content: system_prompt},
      %{role: :user, content: query}
    ],
    model: "openai/gpt-3.5-turbo"
  )

IO.puts("\nAnswer: #{response.content}\n")

# ============================================================================
# Example 3: RAG with Tool Calling
# ============================================================================

IO.puts("2. RAG with Tool Calling")
IO.puts("   LLM can search the knowledge base as needed\n")

# Create a search tool
search_tool =
  Openrouter.Tool.new(
    :search_knowledge_base,
    "Search the knowledge base for relevant information",
    fn %{query: query} ->
      results = SimpleVectorStore.search(store, query, 2)

      formatted_results =
        results
        |> Enum.map(fn result ->
          "Source: #{result.metadata.source}\nContent: #{result.content}\nRelevance: #{Float.round(result.similarity, 3)}"
        end)
        |> Enum.join("\n\n")

      {:ok, formatted_results}
    end,
    parameters: %{
      query: [type: :string, required: true, description: "Search query"]
    }
  )

# Let the agent decide when to search
{:ok, result} =
  Openrouter.Agent.run(
    "Tell me about the BEAM VM and how it relates to Elixir",
    model: "openai/gpt-3.5-turbo",
    tools: [search_tool],
    system: "You are a helpful assistant. Use the search tool to find information before answering."
  )

IO.puts("Answer: #{result.content}\n")

# ============================================================================
# Example 4: RAG with Context-Aware Tools
# ============================================================================

IO.puts("3. RAG with Context-Aware Tools")
IO.puts("   Tools can access conversation history via RunContext\n")

# Dependencies include the vector store
defmodule RAGDeps do
  defstruct [:vector_store, :search_history]
end

# Context-aware search tool
context_search_tool =
  Openrouter.Tool.new(
    :search_docs,
    "Search documentation",
    fn ctx, %{query: query} ->
      # Access the vector store from deps
      results = SimpleVectorStore.search(ctx.deps.vector_store, query, 2)

      # Track search history
      search_entry = %{
        query: query,
        result_count: length(results),
        timestamp: DateTime.utc_now()
      }

      formatted =
        results
        |> Enum.map(&"[#{&1.metadata.source}] #{&1.content}")
        |> Enum.join("\n\n")

      # Return results and update search history
      {:ok, formatted}
    end,
    parameters: %{
      query: [type: :string, required: true]
    },
    context_aware: true
  )

# Create dependencies
deps = %RAGDeps{
  vector_store: store,
  search_history: []
}

{:ok, result} =
  Openrouter.Agent.run(
    "Compare Phoenix and Ecto",
    model: "openai/gpt-3.5-turbo",
    tools: [context_search_tool],
    deps: deps
  )

IO.puts("Answer: #{result.content}\n")

# ============================================================================
# Example 5: Multi-Query RAG
# ============================================================================

IO.puts("4. Multi-Query RAG")
IO.puts("   Generate multiple search queries for better coverage\n")

question = "How does Elixir handle concurrency?"

# Ask LLM to generate multiple search queries
{:ok, query_response} =
  Openrouter.chat(
    """
    Generate 3 different search queries to find information about: "#{question}"

    Return only the queries, one per line, without numbering or explanation.
    """,
    model: "openai/gpt-3.5-turbo"
  )

queries = String.split(query_response.content, "\n", trim: true)
IO.puts("Generated queries:")
Enum.each(queries, fn q -> IO.puts("  - #{q}") end)

# Search with all queries and combine results
all_results =
  queries
  |> Enum.flat_map(fn query ->
    SimpleVectorStore.search(store, query, 2)
  end)
  |> Enum.uniq_by(& &1.id)
  |> Enum.sort_by(& &1.similarity, :desc)
  |> Enum.take(3)

IO.puts("\nCombined top results:")

Enum.each(all_results, fn result ->
  IO.puts("  [#{Float.round(result.similarity, 3)}] #{result.metadata.source}")
end)

# Generate final answer
context = Enum.map_join(all_results, "\n\n", & &1.content)

{:ok, final_answer} =
  Openrouter.chat(
    [
      %{
        role: :system,
        content: "Answer based on the provided context:\n\n#{context}"
      },
      %{role: :user, content: question}
    ],
    model: "openai/gpt-3.5-turbo"
  )

IO.puts("\nFinal Answer: #{final_answer.content}\n")

# ============================================================================
# Example 6: RAG with Conversation Memory
# ============================================================================

IO.puts("5. RAG with Conversation Memory")
IO.puts("   Maintain conversation context with RAG\n")

rag_search_tool =
  Openrouter.Tool.new(
    :search,
    "Search the knowledge base",
    fn %{query: query} ->
      results = SimpleVectorStore.search(store, query, 2)
      {:ok, Enum.map_join(results, "\n\n", & &1.content)}
    end,
    parameters: %{
      query: [type: :string, required: true]
    }
  )

{:ok, conv} =
  Openrouter.Conversation.start(
    model: "openai/gpt-3.5-turbo",
    tools: [rag_search_tool],
    system:
      "You are a helpful assistant. Use the search tool to find information. Be concise."
  )

# First question
conv = Openrouter.Conversation.user(conv, "What is Elixir?")
{:ok, conv, response1} = Openrouter.Conversation.complete_with_agent(conv)
IO.puts("Q1: What is Elixir?")
IO.puts("A1: #{response1.content}\n")

# Follow-up question (uses conversation context)
conv = Openrouter.Conversation.user(conv, "What framework is built with it?")
{:ok, conv, response2} = Openrouter.Conversation.complete_with_agent(conv)
IO.puts("Q2: What framework is built with it?")
IO.puts("A2: #{response2.content}\n")

# ============================================================================
# Example 7: Hybrid Search (Keyword + Semantic)
# ============================================================================

IO.puts("6. Hybrid Search")
IO.puts("   Combine keyword and semantic search\n")

defmodule HybridSearch do
  @doc """
  Performs both keyword and semantic search, then combines results
  """
  def search(store, query, limit \\ 3) do
    # Semantic search (vector similarity)
    semantic_results = SimpleVectorStore.search(store, query, limit * 2)

    # Keyword search (simple string matching)
    query_words =
      query
      |> String.downcase()
      |> String.split()
      |> MapSet.new()

    keyword_results =
      store.documents
      |> Enum.map(fn doc ->
        doc_words =
          doc.content
          |> String.downcase()
          |> String.split()
          |> MapSet.new()

        # Calculate word overlap
        overlap = MapSet.intersection(query_words, doc_words) |> MapSet.size()
        keyword_score = overlap / max(MapSet.size(query_words), 1)

        {doc, keyword_score}
      end)
      |> Enum.filter(fn {_doc, score} -> score > 0 end)
      |> Enum.sort_by(fn {_doc, score} -> score end, :desc)

    # Combine scores (weighted)
    semantic_map = Map.new(semantic_results, fn doc -> {doc.id, doc.similarity} end)
    keyword_map = Map.new(keyword_results, fn {doc, score} -> {doc.id, score} end)

    all_doc_ids =
      MapSet.union(
        MapSet.new(Map.keys(semantic_map)),
        MapSet.new(Map.keys(keyword_map))
      )

    all_doc_ids
    |> Enum.map(fn doc_id ->
      doc = Enum.find(store.documents, &(&1.id == doc_id))
      semantic_score = Map.get(semantic_map, doc_id, 0.0)
      keyword_score = Map.get(keyword_map, doc_id, 0.0)

      # Weighted combination (70% semantic, 30% keyword)
      combined_score = semantic_score * 0.7 + keyword_score * 0.3

      Map.put(doc, :combined_score, combined_score)
    end)
    |> Enum.sort_by(& &1.combined_score, :desc)
    |> Enum.take(limit)
  end
end

query = "Erlang VM BEAM processes"
results = HybridSearch.search(store, query, 3)

IO.puts("Hybrid search for: '#{query}'")

Enum.each(results, fn result ->
  IO.puts(
    "  [#{Float.round(result.combined_score, 3)}] #{String.slice(result.content, 0..60)}..."
  )
end)

IO.puts("")

# ============================================================================
# Example 8: RAG with Reranking
# ============================================================================

IO.puts("7. RAG with Reranking")
IO.puts("   Use LLM to rerank retrieved results\n")

query = "What tools are available for Elixir databases?"

# Initial retrieval (get more candidates)
candidates = SimpleVectorStore.search(store, query, 4)

IO.puts("Initial candidates: #{length(candidates)}")

# Ask LLM to rerank
rerank_prompt = """
Given this query: "#{query}"

Rank the following documents by relevance (1 = most relevant).
Return only the rankings as a JSON array of numbers, e.g., [2, 1, 4, 3]

Documents:
#{Enum.with_index(candidates, 1) |> Enum.map(fn {doc, idx} -> "#{idx}. #{doc.content}" end) |> Enum.join("\n\n")}
"""

{:ok, rerank_response} =
  Openrouter.chat(
    rerank_prompt,
    model: "openai/gpt-3.5-turbo"
  )

IO.puts("Reranked order: #{rerank_response.content}")

# Use top reranked results for final answer
top_results = Enum.take(candidates, 2)
context = Enum.map_join(top_results, "\n\n", & &1.content)

{:ok, final_response} =
  Openrouter.chat(
    [
      %{role: :system, content: "Answer based on context:\n\n#{context}"},
      %{role: :user, content: query}
    ],
    model: "openai/gpt-3.5-turbo"
  )

IO.puts("Answer: #{final_response.content}\n")

# ============================================================================
# Example 9: Production RAG Patterns
# ============================================================================

IO.puts("8. Production RAG Patterns")
IO.puts("   Best practices for production RAG systems\n")

IO.puts("Best Practices:")
IO.puts("1. Vector Database:")
IO.puts("   - Use dedicated vector DB (Qdrant, Pinecone, pgvector)")
IO.puts("   - Index optimization for large datasets")
IO.puts("   - Metadata filtering before vector search")

IO.puts("\n2. Chunking Strategy:")
IO.puts("   - Split documents into 256-512 token chunks")
IO.puts("   - Overlap chunks by 20-50 tokens")
IO.puts("   - Preserve document structure")

IO.puts("\n3. Retrieval:")
IO.puts("   - Retrieve 5-10 candidates initially")
IO.puts("   - Use hybrid search (keyword + semantic)")
IO.puts("   - Rerank with cross-encoder or LLM")
IO.puts("   - Return top 3-5 for context")

IO.puts("\n4. Context Construction:")
IO.puts("   - Format context clearly with sources")
IO.puts("   - Stay within model's context window")
IO.puts("   - Include metadata (source, date, relevance)")

IO.puts("\n5. Answer Generation:")
IO.puts("   - Cite sources in responses")
IO.puts("   - Indicate confidence/uncertainty")
IO.puts("   - Handle 'no relevant info' cases")

IO.puts("\n6. Evaluation:")
IO.puts("   - Track retrieval accuracy")
IO.puts("   - Monitor answer quality")
IO.puts("   - Log user feedback")

IO.puts("\n7. Caching:")
IO.puts("   - Cache embeddings")
IO.puts("   - Cache common queries")
IO.puts("   - Use RunContext to track search history")

IO.puts("")

IO.puts("=== RAG Example Complete ===\n")
