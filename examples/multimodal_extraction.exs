# Multimodal Structured Extraction Example
#
# This example demonstrates how to extract structured data from multimodal content
# (images, videos) using OpenRouter's native structured outputs feature.
#
# Run with: mix run examples/multimodal_extraction.exs

defmodule MultimodalExtractionExample do
  # Define schema for image analysis
  defmodule ImageAnalysisSchema do
    use Openrouter.Schema

    embedded_schema do
      field(:description, :string)
      field(:main_subject, :string)
      field(:colors, {:array, :string})
      field(:objects, {:array, :string})
      field(:mood, :string)
    end

    def changeset(schema, attrs) do
      schema
      |> Ecto.Changeset.cast(attrs, [:description, :main_subject, :colors, :objects, :mood])
      |> Ecto.Changeset.validate_required([:description, :main_subject])
    end
  end

  # Define schema for video analysis
  defmodule VideoAnalysisSchema do
    use Openrouter.Schema

    embedded_schema do
      field(:summary, :string)
      field(:duration_estimate, :integer)
      field(:main_topics, {:array, :string})
      field(:key_moments, {:array, :string})
      field(:language, :string)
    end

    def changeset(schema, attrs) do
      schema
      |> Ecto.Changeset.cast(attrs, [
        :summary,
        :duration_estimate,
        :main_topics,
        :key_moments,
        :language
      ])
      |> Ecto.Changeset.validate_required([:summary])
    end
  end

  def run_image_example do
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Image Analysis with Structured Extraction")
    IO.puts("=" |> String.duplicate(80))

    # Extract structured data from an image
    messages = [
      %{
        role: :user,
        content: [
          Openrouter.Content.text(
            "Analyze this image and provide detailed information about what you see."
          ),
          Openrouter.Content.image_url("https://picsum.photos/800/600")
        ]
      }
    ]

    IO.puts("\nSending request with multimodal content + structured output...")

    case Openrouter.extract(
           messages,
           schema: ImageAnalysisSchema,
           model: "openai/gpt-4o",
           temperature: 0.3
         ) do
      {:ok, analysis} ->
        IO.puts("\n✓ Successfully extracted structured data from image!")
        IO.puts("\nAnalysis:")
        IO.puts("  Description: #{analysis.description}")
        IO.puts("  Main Subject: #{analysis.main_subject}")
        IO.puts("  Colors: #{inspect(analysis.colors)}")
        IO.puts("  Objects: #{inspect(analysis.objects)}")
        IO.puts("  Mood: #{analysis.mood || "N/A"}")

        {:ok, analysis}

      {:error, error} ->
        IO.puts("\n✗ Error: #{inspect(error)}")
        {:error, error}
    end
  end

  def run_video_example(video_path) do
    IO.puts("\n")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Video Analysis with Structured Extraction")
    IO.puts("=" |> String.duplicate(80))

    unless File.exists?(video_path) do
      IO.puts("\n⚠ Video file not found: #{video_path}")
      IO.puts("Please provide a valid video path.")
      return({:error, :file_not_found})
    end

    # Read video file
    video_data = File.read!(video_path)
    format = detect_video_format(video_path)

    IO.puts("\nVideo: #{video_path}")
    IO.puts("Format: #{format}")
    IO.puts("Size: #{byte_size(video_data)} bytes")

    # Extract structured data from video
    messages = [
      %{role: :system, content: "You are an expert video analyst."},
      %{
        role: :user,
        content: [
          Openrouter.Content.text(
            "Analyze this video and provide a comprehensive summary with key details."
          ),
          Openrouter.Content.video(video_data, format: format)
        ]
      }
    ]

    IO.puts("\nSending video for structured analysis...")

    case Openrouter.extract(
           messages,
           schema: VideoAnalysisSchema,
           model: "google/gemini-2.0-flash-exp:free",
           temperature: 0.3,
           max_retries: 3
         ) do
      {:ok, analysis} ->
        IO.puts("\n✓ Successfully extracted structured data from video!")
        IO.puts("\nAnalysis:")
        IO.puts("  Summary: #{analysis.summary}")
        IO.puts("  Duration (est): #{analysis.duration_estimate || "N/A"} seconds")
        IO.puts("  Language: #{analysis.language || "N/A"}")
        IO.puts("  Main Topics: #{inspect(analysis.main_topics || [])}")
        IO.puts("  Key Moments: #{inspect(analysis.key_moments || [])}")

        {:ok, analysis}

      {:error, error} ->
        IO.puts("\n✗ Error: #{inspect(error)}")
        {:error, error}
    end
  end

  def run_custom_prompt_example do
    IO.puts("\n")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Custom System Prompt with Multimodal Extraction")
    IO.puts("=" |> String.duplicate(80))

    # Use custom system prompt with extraction
    messages = [
      %{
        role: :system,
        content: "You are a professional art critic analyzing visual compositions."
      },
      %{
        role: :user,
        content: [
          Openrouter.Content.text(
            "Provide a critical analysis of this image's artistic elements."
          ),
          Openrouter.Content.image_url("https://picsum.photos/800/600")
        ]
      }
    ]

    IO.puts("\nUsing custom system prompt for specialized analysis...")

    case Openrouter.extract(
           messages,
           schema: ImageAnalysisSchema,
           model: "openai/gpt-4o"
         ) do
      {:ok, analysis} ->
        IO.puts("\n✓ Analysis complete!")
        IO.puts("\nCritical Analysis:")
        IO.puts("  #{analysis.description}")

        {:ok, analysis}

      {:error, error} ->
        IO.puts("\n✗ Error: #{inspect(error)}")
        {:error, error}
    end
  end

  defp detect_video_format(path) do
    case Path.extname(path) |> String.downcase() do
      ".mp4" -> :mp4
      ".avi" -> :avi
      ".mov" -> :mov
      ".webm" -> :webm
      ".mpeg" -> :mpeg
      ".mpg" -> :mpeg
      _ -> :mp4
    end
  end

  def run do
    IO.puts("\n🎨 Multimodal Structured Extraction Examples\n")

    # Example 1: Image analysis
    run_image_example()

    # Example 2: Custom prompt
    run_custom_prompt_example()

    # Example 3: Video analysis (if video file exists)
    sample_video = "sample_video.mp4"

    if File.exists?(sample_video) do
      run_video_example(sample_video)
    else
      IO.puts("\n")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("Video Analysis Example (Skipped)")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("\n⚠ No sample video found.")
      IO.puts("To run video extraction, place a video file named 'sample_video.mp4'")
      IO.puts("in the current directory, or modify the script to use your video path.")
    end

    IO.puts("\n")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Key Features Demonstrated")
    IO.puts("=" |> String.duplicate(80))

    IO.puts("""

    ✓ Multimodal content (images, videos) with structured extraction
    ✓ OpenRouter's native response_format for guaranteed JSON structure
    ✓ Ecto schema validation with automatic retries
    ✓ Custom system prompts with structured outputs
    ✓ Support for various image and video formats
    ✓ Type-safe structured data returned as Ecto structs

    The extract/2 function now:
    - Accepts messages list (including multimodal content)
    - Uses response_format parameter automatically
    - Works with both text and multimodal inputs
    - Validates against your Ecto schemas
    """)
  end
end

# Run the examples
MultimodalExtractionExample.run()
