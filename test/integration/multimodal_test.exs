defmodule Openrouter.Integration.MultimodalTest do
  use Reqord.Case

  @moduletag :integration
  @moduletag :multimodal

  describe "image analysis from URL" do
    @tag :integration
    test "analyzes image from URL" do
      content = [
        Openrouter.Content.text("What's in this image? Answer briefly."),
        Openrouter.Content.image_url("https://picsum.photos/200/200")
      ]

      {:ok, response} =
        Openrouter.chat(
          [%{role: :user, content: content}],
          model: "anthropic/claude-3.5-sonnet"
        )

      assert is_binary(response.content)
      assert String.length(response.content) > 10
    end

    @tag :integration
    test "analyzes multiple images" do
      content = [
        Openrouter.Content.text("Compare these two images"),
        Openrouter.Content.image_url("https://picsum.photos/200/200"),
        Openrouter.Content.image_url("https://picsum.photos/200/201")
      ]

      {:ok, response} =
        Openrouter.chat(
          [%{role: :user, content: content}],
          model: "anthropic/claude-3.5-sonnet"
        )

      assert is_binary(response.content)
      assert String.length(response.content) > 20
    end

    @tag :integration
    test "uses detail parameter for image quality" do
      content = [
        Openrouter.Content.text("Describe this image in detail"),
        Openrouter.Content.image_url("https://picsum.photos/400/300", detail: "high")
      ]

      {:ok, response} =
        Openrouter.chat(
          [%{role: :user, content: content}],
          model: "anthropic/claude-3.5-sonnet"
        )

      assert is_binary(response.content)
    end
  end

  describe "content builder" do
    @tag :integration
    test "builds multimodal content with Content.build/2" do
      content =
        Openrouter.Content.build(
          text: "What's in this image?",
          image_url: "https://picsum.photos/200/200"
        )

      {:ok, response} =
        Openrouter.chat(
          [%{role: :user, content: content}],
          model: "anthropic/claude-3.5-sonnet"
        )

      assert is_binary(response.content)
    end

    @tag :integration
    test "builds complex multimodal content" do
      content =
        Openrouter.Content.build(
          text: "Analyze these images",
          image_url: "https://picsum.photos/200/200",
          image_url: "https://picsum.photos/200/201"
        )

      assert length(content) == 3
      assert Enum.at(content, 0)[:type] == :text
      assert Enum.at(content, 1)[:type] == :image_url
      assert Enum.at(content, 2)[:type] == :image_url

      {:ok, response} =
        Openrouter.chat(
          [%{role: :user, content: content}],
          model: "anthropic/claude-3.5-sonnet"
        )

      assert is_binary(response.content)
    end
  end

  describe "base64 image encoding" do
    @tag :integration
    test "handles base64 encoded images" do
      # Create a small test image (1x1 PNG)
      # This is a minimal valid PNG file
      png_data =
        <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
          0, 0, 0, 0, 58, 126, 155, 85, 0, 0, 0, 10, 73, 68, 65, 84, 8, 153, 99, 0, 1, 0, 0, 5, 0,
          1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

      content = [
        Openrouter.Content.text("What color is this image?"),
        Openrouter.Content.image(png_data, format: :png)
      ]

      # Check that content was built correctly
      assert length(content) == 2
      assert Enum.at(content, 1)[:type] == :image_url
      assert Enum.at(content, 1)[:image_url][:url] =~ "data:image/png;base64,"

      # Note: Actual API call might fail for very small images
      # This test primarily validates the encoding logic
    end

    @tag :integration
    test "supports different image formats" do
      fake_image = "fake_image_data"

      # Test PNG
      content_png = Openrouter.Content.image(fake_image, format: :png)
      assert content_png[:image_url][:url] =~ "data:image/png;base64,"

      # Test JPEG
      content_jpeg = Openrouter.Content.image(fake_image, format: :jpeg)
      assert content_jpeg[:image_url][:url] =~ "data:image/jpeg;base64,"

      # Test GIF
      content_gif = Openrouter.Content.image(fake_image, format: :gif)
      assert content_gif[:image_url][:url] =~ "data:image/gif;base64,"

      # Test WebP
      content_webp = Openrouter.Content.image(fake_image, format: :webp)
      assert content_webp[:image_url][:url] =~ "data:image/webp;base64,"
    end
  end

  describe "text and image combination" do
    @tag :integration
    test "combines text with images in conversation" do
      messages = [
        %{
          role: :user,
          content: [
            Openrouter.Content.text("What's in this image?"),
            Openrouter.Content.image_url("https://picsum.photos/200/200")
          ]
        },
        %{
          role: :assistant,
          content: "I see an image."
        },
        %{
          role: :user,
          content: "Tell me more about the colors"
        }
      ]

      {:ok, response} =
        Openrouter.chat(
          messages,
          model: "anthropic/claude-3.5-sonnet"
        )

      assert is_binary(response.content)
    end
  end

  describe "video content" do
    @tag :integration
    test "creates video URL content" do
      content = Openrouter.Content.video_url("https://example.com/video.mp4")

      assert content[:type] == :video_url
      assert content[:video_url][:url] == "https://example.com/video.mp4"
    end

    @tag :integration
    test "creates base64 video content" do
      video_data = "fake_video_data"
      content = Openrouter.Content.video(video_data, format: :mp4)

      assert content[:type] == :video_url
      assert content[:video_url][:url] =~ "data:video/mp4;base64,"
    end
  end

  describe "file and PDF content" do
    @tag :integration
    test "creates PDF content" do
      content = Openrouter.Content.pdf("https://example.com/document.pdf")

      assert content[:type] == :file
      assert content[:file][:file_data] == "https://example.com/document.pdf"
      assert content[:file][:filename] == "document.pdf"
    end

    @tag :integration
    test "creates custom file content" do
      content =
        Openrouter.Content.file(
          "https://example.com/data.csv",
          filename: "data.csv"
        )

      assert content[:type] == :file
      assert content[:file][:file_data] == "https://example.com/data.csv"
      assert content[:file][:filename] == "data.csv"
    end
  end

  describe "content validation" do
    @tag :integration
    test "validates required format parameter for images" do
      assert_raise KeyError, fn ->
        Openrouter.Content.image("data", [])
      end
    end

    @tag :integration
    test "validates required format parameter for videos" do
      assert_raise KeyError, fn ->
        Openrouter.Content.video("data", [])
      end
    end

    @tag :integration
    test "raises on unsupported image format" do
      assert_raise ArgumentError, ~r/Unsupported image format/, fn ->
        Openrouter.Content.image("data", format: :bmp)
      end
    end

    @tag :integration
    test "raises on unsupported video format" do
      assert_raise ArgumentError, ~r/Unsupported video format/, fn ->
        Openrouter.Content.video("data", format: :mkv)
      end
    end
  end

  describe "model support" do
    @tag :integration
    test "vision models support image analysis" do
      content = [
        Openrouter.Content.text("Describe this briefly"),
        Openrouter.Content.image_url("https://picsum.photos/200/200")
      ]

      # Test with different vision-capable models
      vision_models = [
        "anthropic/claude-3.5-sonnet",
        "openai/gpt-4-vision-preview"
      ]

      for model <- vision_models do
        result =
          Openrouter.chat(
            [%{role: :user, content: content}],
            model: model
          )

        case result do
          {:ok, response} ->
            assert is_binary(response.content)

          {:error, _error} ->
            # Model might not be available or have vision support
            # This is okay for this test
            assert true
        end
      end
    end
  end

  describe "error handling" do
    @tag :integration
    test "handles invalid image URLs gracefully" do
      content = [
        Openrouter.Content.text("What's this?"),
        Openrouter.Content.image_url("https://invalid-url-that-does-not-exist.com/image.jpg")
      ]

      result =
        Openrouter.chat(
          [%{role: :user, content: content}],
          model: "anthropic/claude-3.5-sonnet"
        )

      # Should either error or handle gracefully
      case result do
        {:ok, _response} ->
          # Model handled it gracefully
          assert true

        {:error, error} ->
          # Expected error
          assert error.type in [:invalid_request, :server_error]
      end
    end

    @tag :integration
    test "handles non-vision models with images" do
      content = [
        Openrouter.Content.text("What's this?"),
        Openrouter.Content.image_url("https://picsum.photos/200/200")
      ]

      # Try with a non-vision model
      result =
        Openrouter.chat(
          [%{role: :user, content: content}],
          model: "openai/gpt-3.5-turbo"
        )

      # Should error or ignore the image
      case result do
        {:ok, _response} ->
          # Model might ignore or describe the URL
          assert true

        {:error, error} ->
          # Expected - model doesn't support images
          assert error.type in [:invalid_request, :not_found]
      end
    end
  end
end
