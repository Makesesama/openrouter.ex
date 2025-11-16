defmodule Openrouter do
  @moduledoc """
  OpenRouter-focused AI SDK for Elixir.

  This library provides a production-ready client for interacting with AI models
  through OpenRouter, with support for streaming, tool calling, and multimodal content.

  ## Quick Start

      # Simple chat
      {:ok, response} = Openrouter.chat("What is the capital of France?")
      IO.puts(response.content)

      # With specific model
      {:ok, response} = Openrouter.chat(
        "Tell me a joke",
        model: "anthropic/claude-sonnet-4-0",
        temperature: 0.7
      )

      # With conversation history
      messages = [
        %{role: :system, content: "You are a helpful assistant"},
        %{role: :user, content: "Hello!"},
        %{role: :assistant, content: "Hi! How can I help?"},
        %{role: :user, content: "What's the weather?"}
      ]
      {:ok, response} = Openrouter.chat(messages, model: "openai/gpt-4")

  ## Configuration

  Configure the library in your `config/config.exs`:

      config :openrouter,
        api_key: System.get_env("OPENROUTER_API_KEY"),
        default_model: "anthropic/claude-sonnet-4-0",
        app_name: "my-app"

  Or set environment variables:

      export OPENROUTER_API_KEY="or-..."
      export OPENROUTER_DEFAULT_MODEL="anthropic/claude-sonnet-4-0"
  """

  alias Openrouter.{Client, Config}
  alias Openrouter.Types.{Error, Message, Response}

  @type client :: Client.t()
  @type messages :: String.t() | [Message.t()] | [map()]
  @type chat_opts :: [
          model: String.t(),
          temperature: float(),
          max_tokens: pos_integer(),
          top_p: float(),
          frequency_penalty: float(),
          presence_penalty: float(),
          stop: String.t() | [String.t()],
          tools: [map()],
          tool_choice: String.t() | map(),
          timeout: pos_integer()
        ]

  @doc """
  Creates a new client.

  ## Options

    * `:provider` - Provider module (default: `Openrouter.Provider.OpenRouter`)
    * `:model` - Default model to use
    * `:api_key` - API key for authentication
    * `:base_url` - Base URL for the API
    * `:timeout` - Request timeout in milliseconds (default: 60_000)
    * `:app_name` - Application name for OpenRouter tracking
    * `:site_url` - Site URL for OpenRouter tracking

  ## Examples

      client = Openrouter.new()
      # => %Openrouter.Client{...}

      client = Openrouter.new(model: "openai/gpt-4", api_key: "or-...")
      # => %Openrouter.Client{model: "openai/gpt-4", ...}
  """
  @spec new(keyword()) :: client()
  def new(opts \\ []) do
    Client.new(opts)
  end

  @doc """
  Sends a chat completion request.

  ## Arguments

    * `messages` - A string, a list of messages, or a client + messages
    * `opts` - Optional keyword list of parameters

  ## Options

    * `:model` - Model to use (required if not set on client or in config)
    * `:temperature` - Sampling temperature (0.0 to 2.0)
    * `:max_tokens` - Maximum tokens to generate
    * `:top_p` - Nucleus sampling parameter
    * `:frequency_penalty` - Frequency penalty (-2.0 to 2.0)
    * `:presence_penalty` - Presence penalty (-2.0 to 2.0)
    * `:stop` - Stop sequence(s)
    * `:tools` - Function/tool definitions
    * `:tool_choice` - Tool choice mode
    * `:timeout` - Request timeout in milliseconds

  ## Examples

      # Simple string
      {:ok, response} = Openrouter.chat("Hello!")

      # With options
      {:ok, response} = Openrouter.chat("Hello!", model: "openai/gpt-4", temperature: 0.7)

      # With conversation history
      messages = [
        %{role: :user, content: "What's 2+2?"}
      ]
      {:ok, response} = Openrouter.chat(messages, model: "openai/gpt-4")

      # With custom client
      client = Openrouter.new(model: "anthropic/claude-sonnet-4-0")
      {:ok, response} = Openrouter.chat(client, "Hello!")
  """
  @spec chat(client() | messages(), messages() | chat_opts(), chat_opts()) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def chat(client_or_messages, messages_or_opts \\ [], opts \\ [])

  # chat(client, messages, opts)
  def chat(%Client{} = client, messages, opts) when is_list(opts) do
    messages = normalize_messages(messages)
    params = build_params(client, opts)

    client.provider.request(client.config, messages, params)
  end

  # chat(messages, opts)
  def chat(messages, opts, _) when is_list(opts) do
    client = new()
    chat(client, messages, opts)
  end

  # chat(string)
  def chat(message, _, _) when is_binary(message) do
    chat([%{role: :user, content: message}], [])
  end

  @doc """
  Sends a streaming chat completion request.

  Returns a stream that yields chunks as they arrive from the API.

  ## Examples

      # Stream to stdout
      {:ok, stream} = Openrouter.chat_stream("Tell me a story")
      stream
      |> Stream.each(fn
        %{type: :content, content: text} -> IO.write(text)
        %{type: :done} -> IO.puts("\\n[Done]")
      end)
      |> Stream.run()

      # With options
      {:ok, stream} = Openrouter.chat_stream(
        "Write a poem",
        model: "openai/gpt-4",
        temperature: 0.8
      )
  """
  @spec chat_stream(client() | messages(), messages() | chat_opts(), chat_opts()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def chat_stream(client_or_messages, messages_or_opts \\ [], opts \\ [])

  def chat_stream(%Client{} = client, messages, opts) when is_list(opts) do
    messages = normalize_messages(messages)
    params = build_params(client, opts)

    client.provider.request_stream(client.config, messages, params)
  end

  def chat_stream(messages, opts, _) when is_list(opts) do
    client = new()
    chat_stream(client, messages, opts)
  end

  def chat_stream(message, _, _) when is_binary(message) do
    chat_stream([%{role: :user, content: message}], [])
  end

  @doc """
  Generates embeddings for the given text(s).

  ## Examples

      # Single text
      {:ok, [embedding]} = Openrouter.embed("Hello world", model: "text-embedding-3-small")

      # Multiple texts
      {:ok, embeddings} = Openrouter.embed(
        ["Hello", "World"],
        model: "text-embedding-3-small"
      )
  """
  @spec embed(
          client() | String.t() | [String.t()],
          String.t() | [String.t()] | keyword(),
          keyword()
        ) ::
          {:ok, [list(float())]} | {:error, Error.t()}
  def embed(client_or_text, text_or_opts \\ [], opts \\ [])

  def embed(%Client{} = client, texts, opts) when is_list(opts) do
    texts = List.wrap(texts)
    params = build_params(client, opts)

    client.provider.embeddings(client.config, texts, params)
  end

  def embed(texts, opts, _) when is_list(opts) do
    client = new()
    embed(client, texts, opts)
  end

  def embed(text, _, _) when is_binary(text) do
    embed([text], [])
  end

  @doc """
  Extracts structured data from text using an Ecto schema.

  This function uses the LLM to extract structured data and validates it against
  the provided Ecto schema. If validation fails, it automatically retries with
  error feedback to the LLM.

  ## Options

    * `:schema` - Ecto schema module to validate against (required if no :json_schema)
    * `:json_schema` - Raw JSON schema map (alternative to :schema)
    * `:model` - Model to use (required if not set on client or in config)
    * `:max_retries` - Maximum number of retry attempts (default: 3)
    * `:system_prompt` - Custom system prompt for extraction
    * Other chat options (temperature, max_tokens, etc.)

  ## Examples

      # Using an Ecto schema
      defmodule UserSchema do
        use Openrouter.Schema

        embedded_schema do
          field :name, :string
          field :age, :integer
          field :email, :string
        end

        def changeset(schema, attrs) do
          schema
          |> cast(attrs, [:name, :age, :email])
          |> validate_required([:name, :age])
          |> validate_format(:email, ~r/@/)
        end
      end

      {:ok, user} = Openrouter.extract(
        "Extract: John Doe is 30 years old, email john@example.com",
        schema: UserSchema,
        model: "openai/gpt-4"
      )

      # Using a raw JSON schema
      schema = %{
        type: "object",
        properties: %{
          name: %{type: "string"},
          age: %{type: "integer"}
        },
        required: ["name", "age"]
      }

      {:ok, data} = Openrouter.extract(
        "John is 25 years old",
        json_schema: schema,
        model: "openai/gpt-4"
      )
  """
  @spec extract(
          client() | String.t() | messages(),
          String.t() | messages() | keyword(),
          keyword()
        ) ::
          {:ok, struct() | map()} | {:error, Error.t() | Ecto.Changeset.t()}
  def extract(client_or_prompt_or_messages, prompt_or_messages_or_opts \\ [], opts \\ [])

  # Client + messages (list) + opts
  def extract(%Client{} = client, messages, opts) when is_list(messages) and is_list(opts) do
    schema_module = opts[:schema]
    json_schema = opts[:json_schema]
    max_retries = opts[:max_retries] || 3

    cond do
      schema_module && Code.ensure_loaded?(schema_module) ->
        extract_with_ecto_schema(client, messages, schema_module, opts, max_retries)

      json_schema ->
        extract_with_json_schema(client, messages, json_schema, opts, max_retries)

      true ->
        {:error,
         Error.new(
           :validation_error,
           "Either :schema or :json_schema option is required"
         )}
    end
  end

  # Client + string prompt + opts (backward compatibility)
  def extract(%Client{} = client, prompt, opts) when is_binary(prompt) and is_list(opts) do
    # Convert string prompt to messages list
    messages = [%{role: :user, content: prompt}]
    extract(client, messages, opts)
  end

  # Messages (list) + opts
  def extract(messages, opts, _) when is_list(messages) and is_list(opts) do
    client = new()
    extract(client, messages, opts)
  end

  # String prompt + opts (backward compatibility)
  def extract(prompt, opts, _) when is_binary(prompt) and is_list(opts) do
    client = new()
    messages = [%{role: :user, content: prompt}]
    extract(client, messages, opts)
  end

  # Private helpers for extract

  defp extract_with_ecto_schema(client, messages, schema_module, opts, max_retries) do
    # Generate JSON schema from Ecto schema
    json_schema = Openrouter.Schema.to_json_schema(schema_module)

    # Prepare messages - if messages is a string or simple list, wrap properly
    messages = prepare_extraction_messages(messages, opts)

    # Add response_format to opts for structured output
    schema_name = schema_module |> Module.split() |> List.last() |> Macro.underscore()

    extraction_opts =
      opts
      |> Keyword.put(:response_format, %{
        type: "json_schema",
        json_schema: %{
          name: schema_name,
          strict: true,
          schema: json_schema
        }
      })

    # Attempt extraction with retries
    do_extract_with_retries(
      client,
      messages,
      schema_module,
      extraction_opts,
      max_retries,
      0
    )
  end

  defp extract_with_json_schema(client, messages, json_schema, opts, max_retries) do
    # Prepare messages
    messages = prepare_extraction_messages(messages, opts)

    # Add response_format to opts
    extraction_opts =
      opts
      |> Keyword.put(:response_format, %{
        type: "json_schema",
        json_schema: %{
          name: "extraction_result",
          strict: true,
          schema: json_schema
        }
      })

    do_extract_json_with_retries(client, messages, json_schema, extraction_opts, max_retries, 0)
  end

  defp prepare_extraction_messages(messages, opts) when is_list(messages) do
    # Check if messages already has system prompt
    has_system =
      Enum.any?(messages, fn msg ->
        (is_map(msg) and Map.get(msg, :role) == :system) or
          (is_map(msg) and Map.get(msg, "role") == "system")
      end)

    if has_system do
      # User provided their own system prompt, use messages as-is
      messages
    else
      # Add default system prompt for extraction
      system_prompt =
        opts[:system_prompt] ||
          """
          You are a data extraction assistant. Extract the requested information
          and respond with a valid JSON object. The schema will be enforced automatically.
          """

      [%{role: :system, content: system_prompt} | messages]
    end
  end

  defp do_extract_with_retries(_client, _messages, _schema_module, _opts, max_retries, attempt)
       when attempt >= max_retries do
    {:error,
     Error.new(
       :validation_error,
       "Failed to extract valid data after #{max_retries} attempts"
     )}
  end

  defp do_extract_with_retries(client, messages, schema_module, opts, max_retries, attempt) do
    case chat(client, messages, opts) do
      {:ok, response} ->
        handle_response(client, messages, schema_module, opts, max_retries, attempt, response)

      {:error, _} = error ->
        error
    end
  end

  defp handle_response(client, messages, schema_module, opts, max_retries, attempt, response) do
    with {:ok, data} <- parse_json_response(response.content),
         # Ensure data is a map (wrap array if needed for embeds_many at root)
         data <- ensure_map_data(data),
         {:ok, struct} <- Openrouter.Schema.validate(schema_module, data) do
      {:ok, struct}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        # Retry with validation error feedback
        error_message = Openrouter.Schema.format_errors(changeset)

        retry_messages =
          messages ++
            [
              %{role: :assistant, content: response.content},
              %{
                role: :user,
                content:
                  "The previous response had validation errors: #{error_message}. Please provide a corrected response."
              }
            ]

        do_extract_with_retries(
          client,
          retry_messages,
          schema_module,
          opts,
          max_retries,
          attempt + 1
        )

      {:error, _} ->
        # Retry with JSON parsing error feedback
        retry_messages =
          messages ++
            [
              %{role: :assistant, content: response.content},
              %{
                role: :user,
                content:
                  "The previous response was not valid JSON. Please provide a valid JSON object."
              }
            ]

        do_extract_with_retries(
          client,
          retry_messages,
          schema_module,
          opts,
          max_retries,
          attempt + 1
        )
    end
  end

  defp do_extract_json_with_retries(_client, _messages, _json_schema, _opts, max_retries, attempt)
       when attempt >= max_retries do
    {:error,
     Error.new(
       :validation_error,
       "Failed to extract valid JSON after #{max_retries} attempts"
     )}
  end

  defp do_extract_json_with_retries(client, messages, json_schema, opts, max_retries, attempt) do
    case chat(client, messages, opts) do
      {:ok, response} ->
        case parse_json_response(response.content) do
          {:ok, data} ->
            # Basic validation against JSON schema
            # For now, just ensure it's valid JSON
            # Future: Add proper JSON schema validation
            {:ok, data}

          {:error, _} ->
            retry_messages =
              messages ++
                [
                  %{role: :assistant, content: response.content},
                  %{
                    role: :user,
                    content:
                      "The previous response was not valid JSON. Please provide a valid JSON object matching the schema."
                  }
                ]

            do_extract_json_with_retries(
              client,
              retry_messages,
              json_schema,
              opts,
              max_retries,
              attempt + 1
            )
        end

      {:error, _} = error ->
        error
    end
  end

  defp parse_json_response(content) do
    # Try to extract JSON from content (handle markdown code blocks)
    json_str =
      content
      |> String.trim()
      |> extract_json_from_markdown()

    Jason.decode(json_str)
  end

  defp extract_json_from_markdown(content) do
    # Remove markdown code blocks if present
    content
    |> String.replace(~r/^```json\s*/m, "")
    |> String.replace(~r/^```\s*/m, "")
    |> String.trim()
  end

  defp ensure_map_data(data) when is_map(data), do: data

  # Model returned array at root - this shouldn't happen with strict mode
  # but wrap it anyway for robustness
  defp ensure_map_data(data) when is_list(data), do: data

  # Private helpers for messages

  defp normalize_messages(messages) when is_binary(messages) do
    [Message.new(:user, messages)]
  end

  defp normalize_messages(messages) when is_list(messages) do
    Enum.map(messages, fn
      %Message{} = msg ->
        msg

      %{role: role, content: content} = msg ->
        Message.new(
          role,
          content,
          name: msg[:name],
          tool_call_id: msg[:tool_call_id],
          tool_calls: msg[:tool_calls]
        )

      msg when is_map(msg) ->
        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]
        Message.new(role, content)
    end)
  end

  defp build_params(client, opts) do
    # Get model from opts, client, or config
    model = opts[:model] || client.model || Config.get_default_model()

    unless model do
      raise ArgumentError, """
      No model specified. Provide a model in one of the following ways:

      1. Pass it directly: Openrouter.chat("Hello", model: "openai/gpt-4")
      2. Set it on the client: Openrouter.new(model: "openai/gpt-4")
      3. Set default in config: config :openrouter, default_model: "openai/gpt-4"
      """
    end

    %{
      model: model,
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      top_p: opts[:top_p],
      frequency_penalty: opts[:frequency_penalty],
      presence_penalty: opts[:presence_penalty],
      stop: opts[:stop],
      tools: opts[:tools],
      tool_choice: opts[:tool_choice],
      response_format: opts[:response_format],
      timeout: opts[:timeout] || client.timeout
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
