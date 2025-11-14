defmodule Openrouter.ContentTest do
  use ExUnit.Case, async: true

  alias Openrouter.Content

  describe "text/1" do
    test "creates text content item" do
      result = Content.text("Hello world")

      assert result == %{type: :text, text: "Hello world"}
    end
  end

  describe "image_url/2" do
    test "creates image URL content item" do
      result = Content.image_url("https://example.com/image.jpg")

      assert result == %{
               type: :image_url,
               image_url: %{url: "https://example.com/image.jpg"}
             }
    end

    test "creates image URL with detail parameter" do
      result = Content.image_url("https://example.com/image.jpg", detail: "high")

      assert result == %{
               type: :image_url,
               image_url: %{url: "https://example.com/image.jpg", detail: "high"}
             }
    end
  end

  describe "image/2" do
    test "creates base64 encoded image content" do
      image_data = <<137, 80, 78, 71>>
      result = Content.image(image_data, format: :png)

      assert result[:type] == :image_url
      assert result[:image_url][:url] =~ "data:image/png;base64,"
      assert result[:image_url][:url] =~ Base.encode64(image_data)
    end

    test "supports different image formats" do
      image_data = "fake_image_data"

      # JPEG
      result = Content.image(image_data, format: :jpeg)
      assert result[:image_url][:url] =~ "data:image/jpeg;base64,"

      # PNG
      result = Content.image(image_data, format: :png)
      assert result[:image_url][:url] =~ "data:image/png;base64,"

      # GIF
      result = Content.image(image_data, format: :gif)
      assert result[:image_url][:url] =~ "data:image/gif;base64,"

      # WebP
      result = Content.image(image_data, format: :webp)
      assert result[:image_url][:url] =~ "data:image/webp;base64,"
    end

    test "raises on unsupported format" do
      assert_raise ArgumentError, ~r/Unsupported image format/, fn ->
        Content.image("data", format: :bmp)
      end
    end
  end

  describe "video_url/1" do
    test "creates video URL content item" do
      result = Content.video_url("https://example.com/video.mp4")

      assert result == %{
               type: :video_url,
               video_url: %{url: "https://example.com/video.mp4"}
             }
    end
  end

  describe "video/2" do
    test "creates base64 encoded video content" do
      video_data = "fake_video_data"
      result = Content.video(video_data, format: :mp4)

      assert result[:type] == :video_url
      assert result[:video_url][:url] =~ "data:video/mp4;base64,"
      assert result[:video_url][:url] =~ Base.encode64(video_data)
    end

    test "supports different video formats" do
      video_data = "fake_video"

      formats = [:mp4, :mpeg, :mov, :avi, :webm]

      for format <- formats do
        result = Content.video(video_data, format: format)
        assert result[:type] == :video_url
        assert result[:video_url][:url] =~ "data:video/"
      end
    end
  end

  describe "file/2" do
    test "creates file content item" do
      result = Content.file("https://example.com/document.pdf")

      assert result == %{
               type: :file,
               file: %{file_data: "https://example.com/document.pdf"}
             }
    end

    test "creates file with filename" do
      result = Content.file("https://example.com/doc.pdf", filename: "report.pdf")

      assert result[:file][:filename] == "report.pdf"
    end
  end

  describe "pdf/2" do
    test "creates PDF content item" do
      result = Content.pdf("https://example.com/document.pdf")

      assert result[:type] == :file
      assert result[:file][:file_data] == "https://example.com/document.pdf"
      assert result[:file][:filename] == "document.pdf"
    end

    test "accepts custom filename" do
      result = Content.pdf("https://example.com/doc.pdf", filename: "custom.pdf")

      assert result[:file][:filename] == "custom.pdf"
    end
  end

  describe "build/2" do
    test "builds content array from keyword list" do
      result =
        Content.build([
          text: "Hello",
          image_url: "https://example.com/image.jpg"
        ])

      assert length(result) == 2
      assert Enum.at(result, 0) == %{type: :text, text: "Hello"}

      assert Enum.at(result, 1) == %{
               type: :image_url,
               image_url: %{url: "https://example.com/image.jpg"}
             }
    end

    test "builds content with image data" do
      result =
        Content.build(
          [
            text: "Analyze this",
            image: "fake_data"
          ],
          image_format: :jpeg
        )

      assert length(result) == 2
      assert Enum.at(result, 0)[:type] == :text
      assert Enum.at(result, 1)[:type] == :image_url
      assert Enum.at(result, 1)[:image_url][:url] =~ "data:image/jpeg"
    end

    test "builds complex multimodal content" do
      result =
        Content.build([
          text: "Compare these",
          image_url: "https://example.com/img1.jpg",
          image_url: "https://example.com/img2.jpg",
          pdf: "https://example.com/doc.pdf"
        ])

      assert length(result) == 4
      assert Enum.at(result, 0)[:type] == :text
      assert Enum.at(result, 1)[:type] == :image_url
      assert Enum.at(result, 2)[:type] == :image_url
      assert Enum.at(result, 3)[:type] == :file
    end

    test "raises on unknown content type" do
      assert_raise ArgumentError, ~r/Unknown content type/, fn ->
        Content.build([unknown: "value"])
      end
    end
  end
end
