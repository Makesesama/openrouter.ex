defmodule Openrouter.Conversation do
  @moduledoc """
  Stateless conversation management for multi-turn interactions.

  A Conversation manages the message history and state for a conversation
  with an LLM. It provides a functional, immutable API for building and
  executing conversations.

  ## Basic Usage

      # Start a conversation
      {:ok, conversation} = Openrouter.Conversation.start(
        model: "gpt-4",
        system: "You are a helpful assistant"
      )

      # Add a user message
      conversation = Openrouter.Conversation.user(conversation, "Hello!")

      # Get LLM response
      {:ok, conversation, response} = Openrouter.Conversation.complete(conversation)

      # Continue the conversation
      conversation = Openrouter.Conversation.user(conversation, "Tell me more")
      {:ok, conversation, response} = Openrouter.Conversation.complete(conversation)

      # Access message history
      messages = Openrouter.Conversation.messages(conversation)

  ## With Tools

      tools = [weather_tool, calculator_tool]

      {:ok, conversation} = Openrouter.Conversation.start(
        model: "gpt-4",
        tools: tools
      )

      conversation = Openrouter.Conversation.user(conversation, "What's the weather?")
      {:ok, conversation, response} = Openrouter.Conversation.complete(conversation)

  ## Persistence

      # Save conversation to ETS
      :ok = Openrouter.Conversation.save(conversation, to: :ets)

      # Load conversation later
      {:ok, conversation} = Openrouter.Conversation.load(conversation.id, from: :ets)

  ## Immutability

  All functions return new conversation structs. The original is never modified:

      conversation1 = Openrouter.Conversation.user(conv, "Hello")
      conversation2 = Openrouter.Conversation.user(conv, "Hi")

      # conversation1 and conversation2 are different
      # conv is unchanged
  """

  alias Openrouter.Client
  alias Openrouter.Types.{Message, Response}

  @type t :: %__MODULE__{
          id: String.t(),
          client: Client.t(),
          messages: [Message.t() | map()],
          model: String.t() | nil,
          system: String.t() | nil,
          tools: [map()],
          deps: any(),
          temperature: float() | nil,
          max_tokens: integer() | nil,
          metadata: map()
        }

  defstruct [
    :id,
    :client,
    :model,
    :system,
    :temperature,
    :max_tokens,
    :deps,
    messages: [],
    tools: [],
    metadata: %{}
  ]

  @doc """
  Starts a new conversation.

  ## Options

    * `:model` - Model to use for this conversation
    * `:system` - System message/instructions
    * `:tools` - List of tools available in this conversation
    * `:deps` - Dependencies for context-aware tools
    * `:temperature` - Sampling temperature (0.0 to 2.0)
    * `:max_tokens` - Maximum tokens in response
    * `:metadata` - Custom metadata to attach to conversation
    * `:id` - Custom conversation ID (default: auto-generated)

  ## Examples

      {:ok, conv} = Openrouter.Conversation.start(
        model: "gpt-4",
        system: "You are a helpful assistant"
      )

      {:ok, conv} = Openrouter.Conversation.start(
        model: "gpt-4",
        tools: [weather_tool, calculator_tool],
        temperature: 0.7
      )
  """
  @spec start(keyword()) :: {:ok, t()}
  def start(opts \\ []) do
    client = Openrouter.new()

    conversation = %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      client: client,
      model: Keyword.get(opts, :model),
      system: Keyword.get(opts, :system),
      tools: Keyword.get(opts, :tools, []),
      deps: Keyword.get(opts, :deps),
      temperature: Keyword.get(opts, :temperature),
      max_tokens: Keyword.get(opts, :max_tokens),
      metadata: Keyword.get(opts, :metadata, %{}),
      messages: []
    }

    # Add system message if provided
    conversation =
      if conversation.system do
        add_message(conversation, Message.new(:system, conversation.system))
      else
        conversation
      end

    {:ok, conversation}
  end

  @doc """
  Adds a user message to the conversation.

  Returns a new conversation with the message added.

  ## Examples

      conversation = Openrouter.Conversation.user(conv, "Hello!")
      conversation = Openrouter.Conversation.user(conv, "What's the weather?")
  """
  @spec user(t(), String.t()) :: t()
  def user(%__MODULE__{} = conversation, content) when is_binary(content) do
    add_message(conversation, Message.new(:user, content))
  end

  @doc """
  Adds an assistant message to the conversation.

  This is useful for priming the conversation or adding context.

  ## Examples

      conversation = Openrouter.Conversation.assistant(conv, "I'm here to help!")
  """
  @spec assistant(t(), String.t()) :: t()
  def assistant(%__MODULE__{} = conversation, content) when is_binary(content) do
    add_message(conversation, Message.new(:assistant, content))
  end

  @doc """
  Adds a custom message to the conversation.

  ## Examples

      message = %{role: :user, content: "Hello"}
      conversation = Openrouter.Conversation.message(conv, message)
  """
  @spec message(t(), Message.t() | map()) :: t()
  def message(%__MODULE__{} = conversation, message) do
    add_message(conversation, message)
  end

  @doc """
  Completes the conversation by sending messages to the LLM.

  Returns `{:ok, updated_conversation, response}` or `{:error, reason}`.

  The updated conversation includes the assistant's response in the message history.

  ## Examples

      {:ok, conv, response} = Openrouter.Conversation.complete(conversation)
      IO.puts(response.content)

      # With options
      {:ok, conv, response} = Openrouter.Conversation.complete(
        conversation,
        temperature: 0.8,
        max_tokens: 500
      )
  """
  @spec complete(t(), keyword()) :: {:ok, t(), Response.t()} | {:error, any()}
  def complete(%__MODULE__{} = conversation, opts \\ []) do
    # Build options for the chat request
    chat_opts =
      []
      |> maybe_add(:model, conversation.model || opts[:model])
      |> maybe_add(:temperature, conversation.temperature || opts[:temperature])
      |> maybe_add(:max_tokens, conversation.max_tokens || opts[:max_tokens])
      |> maybe_add(:tools, format_tools(conversation.tools))
      |> maybe_add(:deps, conversation.deps)

    # Make the request
    case Openrouter.chat(conversation.client, conversation.messages, chat_opts) do
      {:ok, response} ->
        # Add assistant's response to conversation
        updated_conversation = add_message(conversation, response_to_message(response))
        {:ok, updated_conversation, response}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Completes the conversation using the Agent for automatic tool execution.

  This is useful when tools are involved and you want automatic tool calling.

  Returns `{:ok, updated_conversation, response}` or `{:error, reason}`.

  ## Examples

      {:ok, conv, response} = Openrouter.Conversation.complete_with_agent(
        conversation,
        max_iterations: 5
      )
  """
  @spec complete_with_agent(t(), keyword()) :: {:ok, t(), Response.t()} | {:error, any()}
  def complete_with_agent(%__MODULE__{} = conversation, opts \\ []) do
    # Build options for the agent
    agent_opts =
      []
      |> maybe_add(:model, conversation.model || opts[:model])
      |> maybe_add(:temperature, conversation.temperature || opts[:temperature])
      |> maybe_add(:max_tokens, conversation.max_tokens || opts[:max_tokens])
      |> maybe_add(:tools, conversation.tools)
      |> maybe_add(:deps, conversation.deps)
      |> Keyword.merge(Keyword.take(opts, [:max_iterations, :on_tool_call, :on_tool_result]))

    # Use Agent.run_with_history for automatic tool execution
    case Openrouter.Agent.run_with_history(
           conversation.client,
           conversation.messages,
           agent_opts
         ) do
      {:ok, response} ->
        # Add assistant's response to conversation
        updated_conversation = add_message(conversation, response_to_message(response))
        {:ok, updated_conversation, response}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns the messages in the conversation.

  ## Examples

      messages = Openrouter.Conversation.messages(conversation)
      Enum.each(messages, fn m ->
        IO.inspect(m)
      end)
  """
  @spec messages(t()) :: [Message.t() | map()]
  def messages(%__MODULE__{} = conversation) do
    conversation.messages
  end

  @doc """
  Returns the number of messages in the conversation.

  ## Examples

      count = Openrouter.Conversation.message_count(conversation)
      IO.puts("Message count: " <> Integer.to_string(count))
  """
  @spec message_count(t()) :: non_neg_integer()
  def message_count(%__MODULE__{} = conversation) do
    length(conversation.messages)
  end

  @doc """
  Returns the last N messages from the conversation.

  ## Examples

      last_3 = Openrouter.Conversation.last_messages(conversation, 3)
  """
  @spec last_messages(t(), pos_integer()) :: [Message.t() | map()]
  def last_messages(%__MODULE__{} = conversation, n) when is_integer(n) and n > 0 do
    Enum.take(conversation.messages, -n)
  end

  @doc """
  Clears all messages except the system message (if present).

  Returns a new conversation with messages cleared.

  ## Examples

      conversation = Openrouter.Conversation.clear(conv)
  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = conversation) do
    messages =
      if conversation.system do
        [Message.new(:system, conversation.system)]
      else
        []
      end

    %{conversation | messages: messages}
  end

  @doc """
  Updates conversation metadata.

  ## Examples

      conversation = Openrouter.Conversation.put_metadata(conv, :user_id, 123)
      conversation = Openrouter.Conversation.put_metadata(conv, :session_id, "abc")
  """
  @spec put_metadata(t(), atom(), any()) :: t()
  def put_metadata(%__MODULE__{} = conversation, key, value) do
    %{conversation | metadata: Map.put(conversation.metadata, key, value)}
  end

  @doc """
  Gets a value from conversation metadata.

  ## Examples

      user_id = Openrouter.Conversation.get_metadata(conv, :user_id)
  """
  @spec get_metadata(t(), atom(), any()) :: any()
  def get_metadata(%__MODULE__{} = conversation, key, default \\ nil) do
    Map.get(conversation.metadata, key, default)
  end

  @doc """
  Updates the model for the conversation.

  ## Examples

      conversation = Openrouter.Conversation.update_model(conv, "gpt-4")
  """
  @spec update_model(t(), String.t()) :: t()
  def update_model(%__MODULE__{} = conversation, model) when is_binary(model) do
    %{conversation | model: model}
  end

  @doc """
  Updates the tools available in the conversation.

  ## Examples

      conversation = Openrouter.Conversation.update_tools(conv, [new_tool1, new_tool2])
  """
  @spec update_tools(t(), [any()]) :: t()
  def update_tools(%__MODULE__{} = conversation, tools) when is_list(tools) do
    %{conversation | tools: tools}
  end

  @doc """
  Saves a conversation to a storage backend.

  Currently supports `:ets` backend. Custom backends can be implemented
  by providing a module that implements save/load functions.

  ## Examples

      # Save to ETS
      :ok = Openrouter.Conversation.save(conversation, to: :ets)

      # Save to custom backend
      :ok = Openrouter.Conversation.save(conversation, to: MyApp.ConversationStore)
  """
  @spec save(t(), keyword()) :: :ok | {:error, any()}
  def save(%__MODULE__{} = conversation, opts \\ []) do
    backend = Keyword.get(opts, :to, :ets)

    case backend do
      :ets ->
        save_to_ets(conversation)

      module when is_atom(module) ->
        module.save(conversation)
    end
  end

  @doc """
  Loads a conversation from a storage backend.

  ## Examples

      {:ok, conversation} = Openrouter.Conversation.load(id, from: :ets)
  """
  @spec load(String.t(), keyword()) :: {:ok, t()} | {:error, any()}
  def load(id, opts \\ []) do
    backend = Keyword.get(opts, :from, :ets)

    case backend do
      :ets ->
        load_from_ets(id)

      module when is_atom(module) ->
        module.load(id)
    end
  end

  @doc """
  Deletes a conversation from storage.

  ## Examples

      :ok = Openrouter.Conversation.delete(id, from: :ets)
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, any()}
  def delete(id, opts \\ []) do
    backend = Keyword.get(opts, :from, :ets)

    case backend do
      :ets ->
        delete_from_ets(id)

      module when is_atom(module) ->
        module.delete(id)
    end
  end

  # Private functions

  defp add_message(%__MODULE__{} = conversation, message) do
    %{conversation | messages: conversation.messages ++ [message]}
  end

  defp response_to_message(%Response{} = response) do
    Message.new(
      :assistant,
      response.content,
      tool_calls: response.tool_calls
    )
  end

  defp maybe_add(opts, _key, nil), do: opts

  defp maybe_add(opts, key, value) do
    Keyword.put(opts, key, value)
  end

  defp format_tools([]), do: nil

  defp format_tools(tools) when is_list(tools) do
    Enum.map(tools, fn tool ->
      if is_struct(tool, Openrouter.Tool) do
        Openrouter.Tool.to_openai_format(tool)
      else
        tool
      end
    end)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  # ETS storage backend

  defp ensure_ets_table do
    table = :openrouter_conversations

    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [:set, :public, :named_table])

      _ref ->
        table
    end
  end

  defp save_to_ets(%__MODULE__{} = conversation) do
    table = ensure_ets_table()
    :ets.insert(table, {conversation.id, conversation})
    :ok
  end

  defp load_from_ets(id) do
    table = ensure_ets_table()

    case :ets.lookup(table, id) do
      [{^id, conversation}] -> {:ok, conversation}
      [] -> {:error, :not_found}
    end
  end

  defp delete_from_ets(id) do
    table = ensure_ets_table()
    :ets.delete(table, id)
    :ok
  end
end
