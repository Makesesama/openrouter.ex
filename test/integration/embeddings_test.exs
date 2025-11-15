defmodule Openrouter.Integration.EmbeddingsTest do
  use Reqord.Case

  @moduletag :embeddings

  describe "single text embedding" do
    @tag :integration
    test "generates embedding for single text" do
      {:ok, [embedding]} =
        Openrouter.embed(
          "Hello world",
          model: "text-embedding-3-small"
        )

      assert is_list(embedding)
      assert length(embedding) > 0
      assert Enum.all?(embedding, &is_float/1)
    end

    @tag :integration
    test "embedding has expected dimensions" do
      {:ok, [embedding]} =
        Openrouter.embed(
          "Test text",
          model: "text-embedding-3-small"
        )

      # text-embedding-3-small should have 1536 dimensions
      assert length(embedding) == 1536
    end

    @tag :skip_reqord
    test "different texts produce different embeddings" do
      {:ok, [embedding1]} =
        Openrouter.embed(
          "The quick brown fox",
          model: "text-embedding-3-small"
        )

      {:ok, [embedding2]} =
        Openrouter.embed(
          "Completely different content",
          model: "text-embedding-3-small"
        )

      # Embeddings should be different
      refute embedding1 == embedding2
    end

    @tag :skip_reqord
    test "similar texts produce similar embeddings" do
      {:ok, [embedding1]} =
        Openrouter.embed(
          "I love programming",
          model: "text-embedding-3-small"
        )

      {:ok, [embedding2]} =
        Openrouter.embed(
          "I enjoy coding",
          model: "text-embedding-3-small"
        )

      # Calculate cosine similarity
      similarity = cosine_similarity(embedding1, embedding2)

      # Similar texts should have high similarity (> 0.7)
      assert similarity > 0.7
    end
  end

  describe "batch embeddings" do
    @tag :integration
    test "generates embeddings for multiple texts" do
      texts = ["Hello", "World", "Test"]

      {:ok, embeddings} =
        Openrouter.embed(
          texts,
          model: "text-embedding-3-small"
        )

      assert length(embeddings) == 3
      assert Enum.all?(embeddings, &is_list/1)

      # Each embedding should have the same dimensions
      dimensions = embeddings |> Enum.map(&length/1) |> Enum.uniq()
      assert length(dimensions) == 1
    end

    @tag :skip_reqord
    test "batch embeddings maintain order" do
      texts = ["First", "Second", "Third"]

      {:ok, embeddings} =
        Openrouter.embed(
          texts,
          model: "text-embedding-3-small"
        )

      # Get individual embeddings
      {:ok, [first]} = Openrouter.embed("First", model: "text-embedding-3-small")
      {:ok, [second]} = Openrouter.embed("Second", model: "text-embedding-3-small")

      # First two batch embeddings should match individual ones
      assert_embeddings_similar(Enum.at(embeddings, 0), first)
      assert_embeddings_similar(Enum.at(embeddings, 1), second)
    end

    @tag :integration
    test "handles large batches" do
      texts = for i <- 1..10, do: "Text number #{i}"

      {:ok, embeddings} =
        Openrouter.embed(
          texts,
          model: "text-embedding-3-small"
        )

      assert length(embeddings) == 10

      assert Enum.all?(embeddings, fn emb ->
               is_list(emb) && length(emb) == 1536
             end)
    end

    @tag :integration
    test "handles empty batch" do
      result =
        Openrouter.embed(
          [],
          model: "text-embedding-3-small"
        )

      # Empty input should return an error
      assert {:error, error} = result
      assert error.type == :invalid_request
    end
  end

  describe "embedding dimensions" do
    @tag :integration
    test "all vectors have consistent dimensions" do
      texts = ["Short", "A much longer text with more words", "Medium length"]

      {:ok, embeddings} =
        Openrouter.embed(
          texts,
          model: "text-embedding-3-small"
        )

      dimensions = embeddings |> Enum.map(&length/1) |> Enum.uniq()

      # All embeddings should have the same dimension
      assert length(dimensions) == 1
      assert hd(dimensions) == 1536
    end
  end

  describe "embedding with client" do
    @tag :integration
    test "uses client configuration" do
      client = Openrouter.new()

      {:ok, [embedding]} =
        Openrouter.embed(
          client,
          "Hello world",
          model: "text-embedding-3-small"
        )

      assert is_list(embedding)
      assert length(embedding) == 1536
    end
  end

  describe "semantic similarity" do
    @tag :skip_reqord
    test "finds semantically similar texts" do
      query = "artificial intelligence"

      texts = [
        "machine learning algorithms",
        "pizza recipe instructions",
        "neural networks and deep learning"
      ]

      {:ok, [query_emb]} =
        Openrouter.embed(query, model: "text-embedding-3-small")

      {:ok, text_embs} =
        Openrouter.embed(texts, model: "text-embedding-3-small")

      similarities =
        text_embs
        |> Enum.map(fn emb -> cosine_similarity(query_emb, emb) end)

      # AI-related texts should be more similar to query than pizza recipe
      assert Enum.at(similarities, 0) > Enum.at(similarities, 1)
      assert Enum.at(similarities, 2) > Enum.at(similarities, 1)
    end
  end

  describe "error handling" do
    @tag :integration
    test "handles invalid model" do
      result = Openrouter.embed("Hello", model: "invalid-embedding-model")

      assert {:error, error} = result
      assert error.type in [:invalid_request, :not_found]
    end

    @tag :integration
    test "handles empty text" do
      # Some models might handle empty text, others might error
      result = Openrouter.embed("", model: "text-embedding-3-small")

      case result do
        {:ok, [embedding]} ->
          assert is_list(embedding)

        {:error, _error} ->
          # Also acceptable
          assert true
      end
    end
  end

  describe "special characters and formatting" do
    @tag :integration
    test "handles text with special characters" do
      text = "Hello! How are you? 你好 #hashtag @mention https://example.com"

      {:ok, [embedding]} =
        Openrouter.embed(
          text,
          model: "text-embedding-3-small"
        )

      assert is_list(embedding)
      assert length(embedding) == 1536
    end

    @tag :integration
    test "handles multiline text" do
      text = """
      Line one
      Line two
      Line three
      """

      {:ok, [embedding]} =
        Openrouter.embed(
          text,
          model: "text-embedding-3-small"
        )

      assert is_list(embedding)
      assert length(embedding) == 1536
    end

    @tag :integration
    test "handles very long text" do
      # Create a long text
      text = String.duplicate("word ", 1000)

      {:ok, [embedding]} =
        Openrouter.embed(
          text,
          model: "text-embedding-3-small"
        )

      assert is_list(embedding)
      assert length(embedding) == 1536
    end
  end

  # Helper functions

  defp cosine_similarity(vec1, vec2) do
    dot_product = Enum.zip(vec1, vec2) |> Enum.reduce(0, fn {a, b}, acc -> acc + a * b end)

    magnitude1 = :math.sqrt(Enum.reduce(vec1, 0, fn x, acc -> acc + x * x end))
    magnitude2 = :math.sqrt(Enum.reduce(vec2, 0, fn x, acc -> acc + x * x end))

    dot_product / (magnitude1 * magnitude2)
  end

  defp assert_embeddings_similar(emb1, emb2, threshold \\ 0.99) do
    similarity = cosine_similarity(emb1, emb2)

    assert similarity > threshold,
           "Embeddings should be similar (similarity: #{similarity}, threshold: #{threshold})"
  end
end
