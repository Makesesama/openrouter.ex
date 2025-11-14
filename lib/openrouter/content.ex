defmodule Openrouter.Content do
  @moduledoc """
  Utilities for building multimodal content for messages.

  This module provides helper functions to easily construct content arrays
  that include text, images, videos, and other file types.

  ## Examples

      # Text content
      content = Openrouter.Content.text("What's in this image?")

      # Image from URL
      content = Openrouter.Content.image_url("https://example.com/image.jpg")

      # Local image
      image_data = File.read!("photo.jpg")
      content = Openrouter.Content.image(image_data, format: :jpeg)

      # Build complex content
      content = Openrouter.Content.build([
        text: "Analyze this document and image",
        image: File.read!("chart.png"),
        pdf: "https://example.com/report.pdf"
      ])

      # Use in messages
      messages = [
        %{role: :user, content: content}
      ]
  """

  @type content_item :: map()

  @doc """
  Creates a text content item.

  ## Examples

      iex> Openrouter.Content.text("Hello world")
      %{type: :text, text: "Hello world"}
  """
  @spec text(String.t()) :: content_item()
  def text(text) when is_binary(text) do
    %{type: :text, text: text}
  end

  @doc """
  Creates an image content item from a URL.

  ## Options

    * `:detail` - Level of detail ("auto", "low", "high")

  ## Examples

      iex> Openrouter.Content.image_url("https://example.com/image.jpg")
      %{type: :image_url, image_url: %{url: "https://example.com/image.jpg"}}

      iex> Openrouter.Content.image_url("https://example.com/image.jpg", detail: "high")
      %{type: :image_url, image_url: %{url: "https://example.com/image.jpg", detail: "high"}}
  """
  @spec image_url(String.t(), keyword()) :: content_item()
  def image_url(url, opts \\ []) when is_binary(url) do
    image_url_map = %{url: url}

    image_url_map =
      if detail = opts[:detail] do
        Map.put(image_url_map, :detail, detail)
      else
        image_url_map
      end

    %{type: :image_url, image_url: image_url_map}
  end

  @doc """
  Creates an image content item from binary data.

  The image data will be base64 encoded automatically.

  ## Options

    * `:format` - Image format (:jpeg, :png, :gif, :webp) (required)
    * `:detail` - Level of detail ("auto", "low", "high")

  ## Examples

      iex> image_data = File.read!("photo.jpg")
      iex> Openrouter.Content.image(image_data, format: :jpeg)
      %{type: :image_url, image_url: %{url: "data:image/jpeg;base64,..."}}
  """
  @spec image(binary(), keyword()) :: content_item()
  def image(data, opts) when is_binary(data) do
    format = Keyword.fetch!(opts, :format)
    mime_type = format_to_mime_type(format)
    encoded = Base.encode64(data)
    data_url = "data:#{mime_type};base64,#{encoded}"

    image_url(data_url, detail: opts[:detail])
  end

  @doc """
  Creates a video content item from a URL.

  ## Examples

      iex> Openrouter.Content.video_url("https://example.com/video.mp4")
      %{type: :video_url, video_url: %{url: "https://example.com/video.mp4"}}
  """
  @spec video_url(String.t()) :: content_item()
  def video_url(url) when is_binary(url) do
    %{type: :video_url, video_url: %{url: url}}
  end

  @doc """
  Creates a video content item from binary data.

  ## Options

    * `:format` - Video format (:mp4, :mpeg, :mov, :avi, :webm) (required)

  ## Examples

      iex> video_data = File.read!("clip.mp4")
      iex> Openrouter.Content.video(video_data, format: :mp4)
      %{type: :video_url, video_url: %{url: "data:video/mp4;base64,..."}}
  """
  @spec video(binary(), keyword()) :: content_item()
  def video(data, opts) when is_binary(data) do
    format = Keyword.fetch!(opts, :format)
    mime_type = video_format_to_mime_type(format)
    encoded = Base.encode64(data)
    data_url = "data:#{mime_type};base64,#{encoded}"

    video_url(data_url)
  end

  @doc """
  Creates a file content item (for PDFs and other documents).

  ## Options

    * `:filename` - Original filename (optional)
    * `:type` - MIME type (optional, inferred from URL/filename if not provided)

  ## Examples

      iex> Openrouter.Content.file("https://example.com/document.pdf")
      %{type: :file, file: %{file_data: "https://example.com/document.pdf"}}

      iex> Openrouter.Content.file("https://example.com/doc.pdf", filename: "report.pdf")
      %{type: :file, file: %{file_data: "https://example.com/doc.pdf", filename: "report.pdf"}}
  """
  @spec file(String.t(), keyword()) :: content_item()
  def file(url_or_data, opts \\ []) do
    file_map = %{file_data: url_or_data}

    file_map =
      if filename = opts[:filename] do
        Map.put(file_map, :filename, filename)
      else
        file_map
      end

    %{type: :file, file: file_map}
  end

  @doc """
  Creates a PDF content item from a URL.

  This is a convenience wrapper around `file/2`.

  ## Examples

      iex> Openrouter.Content.pdf("https://example.com/report.pdf")
      %{type: :file, file: %{file_data: "https://example.com/report.pdf", filename: "document.pdf"}}
  """
  @spec pdf(String.t(), keyword()) :: content_item()
  def pdf(url, opts \\ []) do
    opts = Keyword.put_new(opts, :filename, "document.pdf")
    file(url, opts)
  end

  @doc """
  Builds a content array from a keyword list.

  This is a convenient way to construct complex multimodal content.

  ## Supported keys

    * `:text` - String or list of strings
    * `:image` - Binary data (requires `:image_format` option)
    * `:image_url` - URL string or list of URLs
    * `:video` - Binary data (requires `:video_format` option)
    * `:video_url` - URL string
    * `:pdf` - URL string
    * `:file` - URL string

  ## Examples

      iex> Openrouter.Content.build([
      ...>   text: "What's in these images?",
      ...>   image_url: "https://example.com/image1.jpg",
      ...>   image_url: "https://example.com/image2.jpg"
      ...> ])
      [
        %{type: :text, text: "What's in these images?"},
        %{type: :image_url, image_url: %{url: "https://example.com/image1.jpg"}},
        %{type: :image_url, image_url: %{url: "https://example.com/image2.jpg"}}
      ]

      iex> Openrouter.Content.build([
      ...>   text: "Analyze this",
      ...>   image: image_data
      ...> ], image_format: :jpeg)
      [
        %{type: :text, text: "Analyze this"},
        %{type: :image_url, image_url: %{url: "data:image/jpeg;base64,..."}}
      ]
  """
  @spec build(keyword(), keyword()) :: [content_item()]
  def build(items, opts \\ []) do
    items
    |> Enum.map(fn
      {:text, text} ->
        text(text)

      {:image_url, url} ->
        image_url(url)

      {:image, data} ->
        format = Keyword.fetch!(opts, :image_format)
        image(data, format: format)

      {:video_url, url} ->
        video_url(url)

      {:video, data} ->
        format = Keyword.fetch!(opts, :video_format)
        video(data, format: format)

      {:pdf, url} ->
        pdf(url)

      {:file, url} ->
        file(url)

      other ->
        raise ArgumentError, "Unknown content type: #{inspect(other)}"
    end)
  end

  # Private helpers

  defp format_to_mime_type(:jpeg), do: "image/jpeg"
  defp format_to_mime_type(:jpg), do: "image/jpeg"
  defp format_to_mime_type(:png), do: "image/png"
  defp format_to_mime_type(:gif), do: "image/gif"
  defp format_to_mime_type(:webp), do: "image/webp"

  defp format_to_mime_type(format),
    do: raise(ArgumentError, "Unsupported image format: #{inspect(format)}")

  defp video_format_to_mime_type(:mp4), do: "video/mp4"
  defp video_format_to_mime_type(:mpeg), do: "video/mpeg"
  defp video_format_to_mime_type(:mov), do: "video/quicktime"
  defp video_format_to_mime_type(:avi), do: "video/x-msvideo"
  defp video_format_to_mime_type(:webm), do: "video/webm"

  defp video_format_to_mime_type(format),
    do: raise(ArgumentError, "Unsupported video format: #{inspect(format)}")
end
