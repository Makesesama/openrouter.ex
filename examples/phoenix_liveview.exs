#!/usr/bin/env elixir
#
# Phoenix LiveView Integration Example
#
# This example demonstrates how to integrate OpenRouter with Phoenix LiveView
# for building real-time AI chat applications.
#
# This is a complete working example that can be run standalone.
#
# Run with: mix run examples/phoenix_liveview.exs
# Then visit: http://localhost:4000

Mix.install([
  {:openrouter, path: "."},
  {:phoenix, "~> 1.7"},
  {:phoenix_live_view, "~> 0.20"},
  {:plug_cowboy, "~> 2.7"},
  {:jason, "~> 1.4"}
])

# ============================================================================
# LiveView Chat Module
# ============================================================================

defmodule ChatLive do
  use Phoenix.LiveView
  alias Openrouter.ConversationServer

  @impl true
  def mount(_params, _session, socket) do
    # Start a conversation server for this LiveView session
    {:ok, conv_pid} =
      ConversationServer.start_link(
        model: "openai/gpt-3.5-turbo",
        system: "You are a helpful assistant. Keep responses concise and friendly."
      )

    socket =
      socket
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:loading, false)
      |> assign(:conv_pid, conv_pid)
      |> assign(:error, nil)

    {:ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    # Clean up conversation server when LiveView terminates
    if socket.assigns[:conv_pid] do
      ConversationServer.stop(socket.assigns.conv_pid)
    end

    :ok
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) == "" do
      {:noreply, socket}
    else
      # Add user message to UI immediately
      user_msg = %{role: :user, content: message, id: generate_id()}
      messages = socket.assigns.messages ++ [user_msg]

      # Send async request to conversation server
      pid = self()
      conv_pid = socket.assigns.conv_pid

      Task.start(fn ->
        case ConversationServer.send_message(conv_pid, message) do
          {:ok, response} ->
            send(pid, {:ai_response, response.content})

          {:error, error} ->
            send(pid, {:ai_error, error})
        end
      end)

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:input, "")
        |> assign(:loading, true)
        |> assign(:error, nil)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, :input, message)}
  end

  @impl true
  def handle_event("clear_chat", _params, socket) do
    :ok = ConversationServer.clear(socket.assigns.conv_pid)

    socket =
      socket
      |> assign(:messages, [])
      |> assign(:error, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:ai_response, content}, socket) do
    ai_msg = %{role: :assistant, content: content, id: generate_id()}
    messages = socket.assigns.messages ++ [ai_msg]

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:ai_error, error}, socket) do
    error_message = "Error: #{inspect(error)}"

    socket =
      socket
      |> assign(:loading, false)
      |> assign(:error, error_message)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 800px; margin: 0 auto; padding: 20px; font-family: system-ui, -apple-system, sans-serif;">
      <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; border-radius: 12px; margin-bottom: 20px; color: white;">
        <h1 style="margin: 0 0 10px 0; font-size: 32px;">🤖 AI Chat</h1>
        <p style="margin: 0; opacity: 0.9;">Powered by OpenRouter & Phoenix LiveView</p>
      </div>

      <div
        id="messages"
        style="background: #f8f9fa; border-radius: 12px; padding: 20px; min-height: 400px; max-height: 500px; overflow-y: auto; margin-bottom: 20px; border: 1px solid #e9ecef;"
        phx-update="ignore"
      >
        <%= if Enum.empty?(@messages) do %>
          <div style="text-align: center; padding: 60px 20px; color: #6c757d;">
            <div style="font-size: 48px; margin-bottom: 10px;">💬</div>
            <p style="margin: 0;">Start a conversation by typing a message below</p>
          </div>
        <% else %>
          <%= for msg <- @messages do %>
            <div style={"margin-bottom: 16px; display: flex; #{if msg.role == :user, do: "justify-content: flex-end;", else: "justify-content: flex-start;"}"}>
              <div style={"max-width: 70%; padding: 12px 16px; border-radius: 12px; #{if msg.role == :user, do: "background: #667eea; color: white;", else: "background: white; border: 1px solid #e9ecef;"}"}>
                <div style={"font-size: 11px; font-weight: 600; margin-bottom: 4px; text-transform: uppercase; opacity: 0.7; #{if msg.role == :user, do: "color: #fff;", else: "color: #667eea;"}"}>
                  <%= if msg.role == :user, do: "You", else: "Assistant" %>
                </div>
                <div style="line-height: 1.5; white-space: pre-wrap;"><%= msg.content %></div>
              </div>
            </div>
          <% end %>
        <% end %>

        <%= if @loading do %>
          <div style="display: flex; justify-content: flex-start; margin-bottom: 16px;">
            <div style="background: white; border: 1px solid #e9ecef; padding: 12px 16px; border-radius: 12px;">
              <div style="display: flex; gap: 4px;">
                <div style="width: 8px; height: 8px; border-radius: 50%; background: #667eea; animation: bounce 1s infinite;"></div>
                <div style="width: 8px; height: 8px; border-radius: 50%; background: #667eea; animation: bounce 1s infinite 0.2s;"></div>
                <div style="width: 8px; height: 8px; border-radius: 50%; background: #667eea; animation: bounce 1s infinite 0.4s;"></div>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @error do %>
        <div style="background: #f8d7da; border: 1px solid #f5c2c7; color: #842029; padding: 12px 16px; border-radius: 8px; margin-bottom: 16px;">
          <%= @error %>
        </div>
      <% end %>

      <form phx-submit="send_message" style="display: flex; gap: 12px; margin-bottom: 12px;">
        <input
          type="text"
          name="message"
          value={@input}
          phx-change="update_input"
          placeholder="Type your message..."
          disabled={@loading}
          style="flex: 1; padding: 12px 16px; border: 2px solid #e9ecef; border-radius: 8px; font-size: 16px; outline: none; transition: border-color 0.2s;"
        />
        <button
          type="submit"
          disabled={@loading || String.trim(@input) == ""}
          style={"padding: 12px 24px; background: #667eea; color: white; border: none; border-radius: 8px; font-size: 16px; font-weight: 600; cursor: pointer; transition: all 0.2s; #{if @loading || String.trim(@input) == "", do: "opacity: 0.5; cursor: not-allowed;", else: ""}"}
        >
          <%= if @loading, do: "Sending...", else: "Send" %>
        </button>
      </form>

      <div style="display: flex; justify-content: space-between; align-items: center;">
        <button
          phx-click="clear_chat"
          style="padding: 8px 16px; background: transparent; color: #6c757d; border: 1px solid #dee2e6; border-radius: 6px; font-size: 14px; cursor: pointer; transition: all 0.2s;"
        >
          🗑️ Clear Chat
        </button>
        <div style="color: #6c757d; font-size: 14px;">
          <%= length(@messages) %> messages
        </div>
      </div>

      <style>
        @keyframes bounce {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(-8px); }
        }

        input:focus {
          border-color: #667eea !important;
        }

        button:not(:disabled):hover {
          transform: translateY(-1px);
          box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
        }
      </style>
    </div>
    """
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
end

# ============================================================================
# Streaming Chat LiveView
# ============================================================================

defmodule StreamingChatLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:streaming, false)
      |> assign(:current_response, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) == "" do
      {:noreply, socket}
    else
      # Add user message
      user_msg = %{role: :user, content: message, id: generate_id()}
      messages = socket.assigns.messages ++ [user_msg]

      # Start streaming
      pid = self()

      Task.start(fn ->
        case Openrouter.chat_stream(message, model: "openai/gpt-3.5-turbo") do
          {:ok, stream} ->
            Enum.each(stream, fn chunk ->
              if chunk.content do
                send(pid, {:stream_chunk, chunk.content})
              end
            end)

            send(pid, :stream_done)

          {:error, error} ->
            send(pid, {:stream_error, error})
        end
      end)

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:input, "")
        |> assign(:streaming, true)
        |> assign(:current_response, "")

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, :input, message)}
  end

  @impl true
  def handle_info({:stream_chunk, content}, socket) do
    current = socket.assigns.current_response
    {:noreply, assign(socket, :current_response, current <> content)}
  end

  @impl true
  def handle_info(:stream_done, socket) do
    # Add completed response to messages
    ai_msg = %{role: :assistant, content: socket.assigns.current_response, id: generate_id()}
    messages = socket.assigns.messages ++ [ai_msg]

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:streaming, false)
      |> assign(:current_response, "")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_error, error}, socket) do
    IO.puts("Stream error: #{inspect(error)}")

    socket =
      socket
      |> assign(:streaming, false)
      |> assign(:current_response, "")

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 800px; margin: 0 auto; padding: 20px;">
      <h1>Streaming Chat</h1>

      <div id="messages" style="border: 1px solid #ccc; padding: 20px; min-height: 400px; margin-bottom: 20px;">
        <%= for msg <- @messages do %>
          <div style={"margin-bottom: 10px; color: #{if msg.role == :user, do: "blue", else: "green"}"}>
            <strong><%= msg.role %>:</strong>
            <%= msg.content %>
          </div>
        <% end %>

        <%= if @streaming do %>
          <div style="margin-bottom: 10px; color: green;">
            <strong>assistant:</strong>
            <%= @current_response %>
            <span style="animation: blink 1s infinite;">▊</span>
          </div>
        <% end %>
      </div>

      <form phx-submit="send_message" style="display: flex; gap: 10px;">
        <input
          type="text"
          name="message"
          value={@input}
          phx-change="update_input"
          placeholder="Type a message..."
          disabled={@streaming}
          style="flex: 1; padding: 10px;"
        />
        <button type="submit" disabled={@streaming} style="padding: 10px 20px;">
          <%= if @streaming, do: "Streaming...", else: "Send" %>
        </button>
      </form>

      <style>
        @keyframes blink {
          0%, 50% { opacity: 1; }
          51%, 100% { opacity: 0; }
        }
      </style>
    </div>
    """
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
end

# ============================================================================
# Phoenix Router and Endpoint
# ============================================================================

defmodule Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", ThisApp do
    pipe_through(:browser)

    live("/", ChatLive)
    live("/streaming", StreamingChatLive)
  end
end

defmodule LayoutView do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>OpenRouter Phoenix Example</title>
        <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.10/priv/static/phoenix.min.js">
        </script>
        <script
          src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.20.2/priv/static/phoenix_live_view.min.js"
        >
        </script>
        <script>
          let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket)
          liveSocket.connect()
        </script>
      </head>
      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end
end

defmodule Endpoint do
  use Phoenix.Endpoint, otp_app: :sample

  socket("/live", Phoenix.LiveView.Socket)

  plug(Plug.Session,
    store: :cookie,
    key: "_app_key",
    signing_salt: "secret_salt_change_me"
  )

  plug(Router)
end

# ============================================================================
# Application and Supervisor
# ============================================================================

defmodule ThisApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: ThisApp.PubSub},
      Endpoint
    ]

    opts = [strategy: :one_for_one, name: ThisApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

# ============================================================================
# Configuration and Startup
# ============================================================================

Application.put_env(:sample, Endpoint,
  http: [port: 4000],
  server: true,
  live_view: [signing_salt: "secret_salt"],
  secret_key_base: String.duplicate("a", 64),
  pubsub_server: ThisApp.PubSub
)

Application.put_env(:phoenix, :json_library, Jason)

IO.puts("""

================================================================================
🚀 Phoenix LiveView + OpenRouter Example

Starting server on http://localhost:4000

Available routes:
  • http://localhost:4000           - Main chat interface
  • http://localhost:4000/streaming - Streaming chat example

Features demonstrated:
  ✓ Real-time chat with LiveView
  ✓ ConversationServer integration
  ✓ Async message handling
  ✓ Streaming responses
  ✓ Clean UI with loading states
  ✓ Error handling
  ✓ Chat history management

Press Ctrl+C to stop the server
================================================================================

""")

{:ok, _} = ThisApp.Application.start(:normal, [])

Process.sleep(:infinity)
