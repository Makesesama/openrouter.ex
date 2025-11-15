defmodule Openrouter.Provider do
  @moduledoc """
  Behavior for AI model providers.

  OpenRouter is the default and primary provider.
  Implement this behavior if you need to use a different provider.

  ## Example

      defmodule MyApp.CustomProvider do
        @behaviour Openrouter.Provider

        @impl true
        def name, do: "custom"

        @impl true
        def request(config, messages, params) do
          # Custom implementation
          {:ok, response}
        end

        @impl true
        def request_stream(config, messages, params) do
          # Custom streaming implementation
          {:ok, stream}
        end

        @impl true
        def embeddings(config, texts, params) do
          # Custom embeddings implementation
          {:ok, embeddings}
        end
      end

      # Use custom provider
      client = Openrouter.new(provider: MyApp.CustomProvider)
  """

  alias Openrouter.Types.{Error, Message, Response}

  @type config :: map()
  @type params :: map()

  @doc """
  Returns the name of the provider.
  """
  @callback name() :: String.t()

  @doc """
  Makes a chat completion request.

  Returns a Response struct or an error.
  """
  @callback request(config(), [Message.t()], params()) ::
              {:ok, Response.t()} | {:error, Error.t()}

  @doc """
  Makes a streaming chat completion request.

  Returns a stream of response chunks or an error.
  """
  @callback request_stream(config(), [Message.t()], params()) ::
              {:ok, Enumerable.t()} | {:error, Error.t()}

  @doc """
  Generates embeddings for the given texts.

  Returns a list of embedding vectors or an error.
  """
  @callback embeddings(config(), [String.t()], params()) ::
              {:ok, [list(float())]} | {:error, Error.t()}

  @optional_callbacks embeddings: 3
end
