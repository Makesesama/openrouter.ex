defmodule Openrouter.ConversationServer do
  @moduledoc """
  GenServer-based stateful conversation management.

  ConversationServer wraps a Conversation in a GenServer, providing stateful
  conversation management with automatic message history tracking.

  ## Basic Usage

      # Start a conversation server
      {:ok, pid} = Openrouter.ConversationServer.start_link(
        model: "gpt-4",
        system: "You are a helpful assistant"
      )

      # Send a message
      {:ok, response} = Openrouter.ConversationServer.send_message(pid, "Hello!")

      # Get conversation history
      messages = Openrouter.ConversationServer.get_messages(pid)

      # Clear history
      :ok = Openrouter.ConversationServer.clear(pid)

  ## With Registry

      defmodule MyApp.ChatSession do
        use Openrouter.ConversationServer

        def start_link(user_id) do
          Openrouter.ConversationServer.start_link(
            __MODULE__,
            name: via_tuple(user_id),
            model: "gpt-4",
            system: "You are a helpful assistant"
          )
        end

        defp via_tuple(user_id) do
          {:via, Registry, {MyApp.Registry, {__MODULE__, user_id}}}
        end
      end

      # Start for a user
      {:ok, _pid} = MyApp.ChatSession.start_link(123)

      # Send message using registry
      {:ok, response} = Openrouter.ConversationServer.send_message(
        {:via, Registry, {MyApp.Registry, {MyApp.ChatSession, 123}}},
        "Hello!"
      )

  ## With Tools

      {:ok, pid} = Openrouter.ConversationServer.start_link(
        model: "gpt-4",
        tools: [weather_tool, calculator_tool],
        use_agent: true  # Enable automatic tool execution
      )

      {:ok, response} = Openrouter.ConversationServer.send_message(
        pid,
        "What's the weather in Paris?"
      )

  ## Streaming

      {:ok, pid} = Openrouter.ConversationServer.start_link(model: "gpt-4")

      # Stream to calling process
      :ok = Openrouter.ConversationServer.send_message_stream(
        pid,
        "Tell me a story",
        stream_to: self()
      )

      # Receive chunks
      receive do
        {:stream_chunk, chunk} -> IO.write(chunk)
        {:stream_done, response} -> IO.puts("\nDone!")
      end
  """

  use GenServer
  require Logger

  alias Openrouter.Conversation
  alias Openrouter.Types.Response

  @type server_ref :: pid() | atom() | {:via, module(), term()}

  defstruct [:conversation, :opts]

  ## Client API

  @doc """
  Starts a conversation server.

  ## Options

    * `:model` - Model to use
    * `:system` - System message
    * `:tools` - List of tools
    * `:deps` - Dependencies for context-aware tools
    * `:use_agent` - Use Agent for automatic tool execution (default: false)
    * `:temperature` - Sampling temperature
    * `:max_tokens` - Maximum tokens in response
    * `:name` - Registration name for the server
    * `:metadata` - Custom metadata

  ## Examples

      {:ok, pid} = Openrouter.ConversationServer.start_link(
        model: "gpt-4",
        system: "You are a helpful assistant"
      )

      {:ok, pid} = Openrouter.ConversationServer.start_link(
        model: "gpt-4",
        tools: [weather_tool],
        use_agent: true,
        name: MyConversation
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, conversation_opts} = split_opts(opts)
    GenServer.start_link(__MODULE__, conversation_opts, gen_opts)
  end

  @spec start_link(module(), keyword()) :: GenServer.on_start()
  def start_link(_module, opts) do
    # Support "use Openrouter.ConversationServer" pattern
    start_link(opts)
  end

  @doc """
  Sends a message and gets a response.

  Returns `{:ok, response}` or `{:error, reason}`.

  ## Examples

      {:ok, response} = Openrouter.ConversationServer.send_message(
        pid,
        "What is 2 + 2?"
      )

      IO.puts(response.content)
  """
  @spec send_message(server_ref(), String.t(), keyword()) ::
          {:ok, Response.t()} | {:error, any()}
  def send_message(server, content, opts \\ []) do
    GenServer.call(server, {:send_message, content, opts}, :infinity)
  end

  @doc """
  Sends a message and streams the response.

  The stream is sent to the process specified in `:stream_to` option
  (default: calling process).

  Messages sent:
    - `{:stream_chunk, chunk}` - For each chunk of the response
    - `{:stream_done, response}` - When streaming is complete
    - `{:stream_error, error}` - If an error occurs

  ## Examples

      :ok = Openrouter.ConversationServer.send_message_stream(
        pid,
        "Tell me a story",
        stream_to: self()
      )

      # Receive chunks
      receive do
        {:stream_chunk, chunk} -> IO.write(chunk.content)
        {:stream_done, response} -> IO.puts("\nDone!")
        {:stream_error, err} -> IO.puts("Error occurred")
      end
  """
  @spec send_message_stream(server_ref(), String.t(), keyword()) :: :ok
  def send_message_stream(server, content, opts \\ []) do
    GenServer.cast(server, {:send_message_stream, content, opts})
  end

  @doc """
  Gets the current conversation messages.

  ## Examples

      messages = Openrouter.ConversationServer.get_messages(pid)
      Enum.each(messages, fn m ->
        IO.inspect(m)
      end)
  """
  @spec get_messages(server_ref()) :: [map()]
  def get_messages(server) do
    GenServer.call(server, :get_messages)
  end

  @doc """
  Gets the message count.

  ## Examples

      count = Openrouter.ConversationServer.message_count(pid)
  """
  @spec message_count(server_ref()) :: non_neg_integer()
  def message_count(server) do
    GenServer.call(server, :message_count)
  end

  @doc """
  Gets the current conversation state.

  ## Examples

      conversation = Openrouter.ConversationServer.get_conversation(pid)
      IO.inspect(conversation)
  """
  @spec get_conversation(server_ref()) :: Conversation.t()
  def get_conversation(server) do
    GenServer.call(server, :get_conversation)
  end

  @doc """
  Clears all messages (except system message).

  ## Examples

      :ok = Openrouter.ConversationServer.clear(pid)
  """
  @spec clear(server_ref()) :: :ok
  def clear(server) do
    GenServer.call(server, :clear)
  end

  @doc """
  Updates the model used for the conversation.

  ## Examples

      :ok = Openrouter.ConversationServer.update_model(pid, "gpt-4")
  """
  @spec update_model(server_ref(), String.t()) :: :ok
  def update_model(server, model) do
    GenServer.call(server, {:update_model, model})
  end

  @doc """
  Updates the tools available in the conversation.

  ## Examples

      :ok = Openrouter.ConversationServer.update_tools(pid, [new_tool])
  """
  @spec update_tools(server_ref(), [any()]) :: :ok
  def update_tools(server, tools) do
    GenServer.call(server, {:update_tools, tools})
  end

  @doc """
  Sets metadata on the conversation.

  ## Examples

      :ok = Openrouter.ConversationServer.put_metadata(pid, :user_id, 123)
  """
  @spec put_metadata(server_ref(), atom(), any()) :: :ok
  def put_metadata(server, key, value) do
    GenServer.call(server, {:put_metadata, key, value})
  end

  @doc """
  Gets metadata from the conversation.

  ## Examples

      user_id = Openrouter.ConversationServer.get_metadata(pid, :user_id)
  """
  @spec get_metadata(server_ref(), atom(), any()) :: any()
  def get_metadata(server, key, default \\ nil) do
    GenServer.call(server, {:get_metadata, key, default})
  end

  @doc """
  Stops the conversation server.

  ## Examples

      :ok = Openrouter.ConversationServer.stop(pid)
  """
  @spec stop(server_ref()) :: :ok
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    {:ok, conversation} = Conversation.start(opts)

    state = %__MODULE__{
      conversation: conversation,
      opts: Keyword.take(opts, [:use_agent, :on_tool_call, :on_tool_result, :max_iterations])
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, content, opts}, _from, state) do
    # Add user message
    conversation = Conversation.user(state.conversation, content)

    # Complete the conversation
    result =
      if Keyword.get(state.opts, :use_agent, false) do
        # Use agent for automatic tool execution
        agent_opts = Keyword.merge(state.opts, opts)
        Conversation.complete_with_agent(conversation, agent_opts)
      else
        # Regular completion
        Conversation.complete(conversation, opts)
      end

    case result do
      {:ok, updated_conversation, response} ->
        new_state = %{state | conversation: updated_conversation}
        {:reply, {:ok, response}, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_messages, _from, state) do
    messages = Conversation.messages(state.conversation)
    {:reply, messages, state}
  end

  @impl true
  def handle_call(:message_count, _from, state) do
    count = Conversation.message_count(state.conversation)
    {:reply, count, state}
  end

  @impl true
  def handle_call(:get_conversation, _from, state) do
    {:reply, state.conversation, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    conversation = Conversation.clear(state.conversation)
    {:reply, :ok, %{state | conversation: conversation}}
  end

  @impl true
  def handle_call({:update_model, model}, _from, state) do
    conversation = Conversation.update_model(state.conversation, model)
    {:reply, :ok, %{state | conversation: conversation}}
  end

  @impl true
  def handle_call({:update_tools, tools}, _from, state) do
    conversation = Conversation.update_tools(state.conversation, tools)
    {:reply, :ok, %{state | conversation: conversation}}
  end

  @impl true
  def handle_call({:put_metadata, key, value}, _from, state) do
    conversation = Conversation.put_metadata(state.conversation, key, value)
    {:reply, :ok, %{state | conversation: conversation}}
  end

  @impl true
  def handle_call({:get_metadata, key, default}, _from, state) do
    value = Conversation.get_metadata(state.conversation, key, default)
    {:reply, value, state}
  end

  @impl true
  def handle_cast({:send_message_stream, content, opts}, state) do
    stream_to = Keyword.get(opts, :stream_to, self())

    # Add user message
    conversation = Conversation.user(state.conversation, content)

    # Start streaming task
    Task.start(fn ->
      stream_opts =
        []
        |> maybe_add(:model, conversation.model)
        |> maybe_add(:temperature, conversation.temperature)
        |> maybe_add(:max_tokens, conversation.max_tokens)

      case Openrouter.chat_stream(
             conversation.client,
             conversation.messages,
             stream_opts
           ) do
        {:ok, stream} ->
          # Send chunks to the stream_to process
          for chunk <- stream do
            send(stream_to, {:stream_chunk, chunk})
          end

          send(stream_to, {:stream_done, :ok})

        {:error, error} ->
          send(stream_to, {:stream_error, error})
      end
    end)

    {:noreply, %{state | conversation: conversation}}
  end

  # Private helpers

  defp split_opts(opts) do
    gen_opts = Keyword.take(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    conversation_opts =
      Keyword.drop(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    {gen_opts, conversation_opts}
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  ## Macro for "use" pattern

  defmacro __using__(_opts) do
    quote do
      @doc false
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :worker,
          restart: :permanent,
          shutdown: 5000
        }
      end

      defoverridable child_spec: 1
    end
  end
end
