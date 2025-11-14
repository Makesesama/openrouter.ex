defmodule Openrouter.Agent do
  @moduledoc """
  High-level agent interface with automatic tool execution.

  Agents automatically handle the tool calling loop:
  1. Send message with available tools to LLM
  2. LLM responds with tool calls (or final answer)
  3. Execute tools and send results back
  4. Repeat until LLM provides final answer

  ## Basic Usage

      # Define tools
      tools = [
        Openrouter.Tool.new(
          :get_weather,
          "Get weather for a location",
          fn %{location: loc} ->
            {:ok, "Sunny, 72°F in #{loc}"}
          end,
          parameters: %{
            location: [type: :string, required: true]
          }
        )
      ]

      # Run agent
      {:ok, result} = Openrouter.Agent.run(
        "What's the weather in Paris?",
        model: "openai/gpt-4",
        tools: tools
      )

      IO.puts(result.content)
      # => "The weather in Paris is sunny and 72°F"

  ## With System Instructions

      {:ok, result} = Openrouter.Agent.run(
        "Help me with my task",
        model: "openai/gpt-4",
        tools: tools,
        system: "You are a helpful assistant"
      )

  ## Max Iterations

  To prevent infinite loops, agents have a maximum iteration limit:

      {:ok, result} = Openrouter.Agent.run(
        prompt,
        model: "gpt-4",
        tools: tools,
        max_iterations: 10  # Default is 5
      )

  ## Tool Execution Callbacks

  Monitor tool execution with callbacks:

      {:ok, result} = Openrouter.Agent.run(
        prompt,
        tools: tools,
        on_tool_call: fn tool_call ->
          IO.puts("Calling tool: #{tool_call.function.name}")
        end,
        on_tool_result: fn tool_call, result ->
          IO.puts("Tool #{tool_call.function.name} returned: #{inspect(result)}")
        end
      )
  """

  alias Openrouter.{Tool, Client}
  alias Openrouter.Types.{Message, Response, ToolCall}

  require Logger

  @default_max_iterations 5

  @type run_opts :: [
          model: String.t(),
          tools: [Tool.t()],
          system: String.t(),
          max_iterations: pos_integer(),
          on_tool_call: (ToolCall.t() -> any()),
          on_tool_result: (ToolCall.t(), any() -> any()),
          temperature: float(),
          max_tokens: pos_integer()
        ]

  @doc """
  Runs an agent with automatic tool execution.

  The agent will:
  1. Send the prompt with tools to the LLM
  2. Execute any tool calls
  3. Send results back to the LLM
  4. Repeat until a final answer is reached or max_iterations is hit

  Returns `{:ok, response}` with the final LLM response, or `{:error, reason}`.

  ## Options

    * `:model` - Model to use (required)
    * `:tools` - List of Tool structs available to the agent
    * `:system` - System message/instructions
    * `:max_iterations` - Maximum tool calling iterations (default: 5)
    * `:on_tool_call` - Callback when a tool is about to be called
    * `:on_tool_result` - Callback when a tool returns a result
    * Other chat options (temperature, max_tokens, etc.)

  ## Examples

      tools = [
        Openrouter.Tool.new(:add, "Add two numbers", fn %{a: a, b: b} ->
          {:ok, a + b}
        end, parameters: %{
          a: [type: :number, required: true],
          b: [type: :number, required: true]
        })
      ]

      {:ok, result} = Openrouter.Agent.run(
        "What is 25 + 17?",
        model: "openai/gpt-4",
        tools: tools
      )
  """
  @spec run(String.t() | Client.t(), String.t() | run_opts(), run_opts()) ::
          {:ok, Response.t()} | {:error, any()}
  def run(client_or_prompt, prompt_or_opts \\ [], opts \\ [])

  def run(%Client{} = client, prompt, opts) when is_binary(prompt) do
    # Build initial messages
    messages = build_initial_messages(prompt, opts)

    # Extract options
    tools = Keyword.get(opts, :tools, [])
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    on_tool_call = Keyword.get(opts, :on_tool_call)
    on_tool_result = Keyword.get(opts, :on_tool_result)

    # Validate we have tools
    if tools == [] do
      Logger.warning("Agent.run called without tools, using simple chat instead")
      Openrouter.chat(client, messages, opts)
    else
      # Run the agent loop
      run_loop(client, messages, tools, max_iterations, opts, %{
        on_tool_call: on_tool_call,
        on_tool_result: on_tool_result,
        iteration: 0
      })
    end
  end

  def run(prompt, opts, _) when is_binary(prompt) and is_list(opts) do
    client = Openrouter.new()
    run(client, prompt, opts)
  end

  @doc """
  Runs an agent loop with conversation history.

  Similar to `run/3` but accepts a list of messages instead of a single prompt.

  ## Examples

      messages = [
        %{role: :system, content: "You are a helpful assistant"},
        %{role: :user, content: "Help me calculate something"},
        %{role: :assistant, content: "I can help with calculations"},
        %{role: :user, content: "What is 15 times 8?"}
      ]

      {:ok, result} = Openrouter.Agent.run_with_history(
        messages,
        model: "openai/gpt-4",
        tools: [calculator_tool]
      )
  """
  @spec run_with_history(Client.t() | [map()], [map()] | run_opts(), run_opts()) ::
          {:ok, Response.t()} | {:error, any()}
  def run_with_history(client_or_messages, messages_or_opts \\ [], opts \\ [])

  def run_with_history(%Client{} = client, messages, opts)
      when is_list(messages) and is_list(opts) do
    tools = Keyword.get(opts, :tools, [])
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    on_tool_call = Keyword.get(opts, :on_tool_call)
    on_tool_result = Keyword.get(opts, :on_tool_result)

    # Normalize messages
    normalized_messages = Openrouter.normalize_messages(messages)

    run_loop(client, normalized_messages, tools, max_iterations, opts, %{
      on_tool_call: on_tool_call,
      on_tool_result: on_tool_result,
      iteration: 0
    })
  end

  def run_with_history(messages, opts, _) when is_list(messages) and is_list(opts) do
    client = Openrouter.new()
    run_with_history(client, messages, opts)
  end

  # Private functions

  defp build_initial_messages(prompt, opts) do
    messages = []

    messages =
      if system = Keyword.get(opts, :system) do
        [Message.new(:system, system) | messages]
      else
        messages
      end

    messages ++ [Message.new(:user, prompt)]
  end

  defp run_loop(_client, _messages, _tools, max_iterations, _opts, %{iteration: iteration} = _state)
       when iteration >= max_iterations do
    {:error, "Maximum iterations (#{max_iterations}) reached without final answer"}
  end

  defp run_loop(client, messages, tools, max_iterations, opts, state) do
    # Convert tools to OpenAI format
    tool_specs = Enum.map(tools, &Tool.to_openai_format/1)

    # Make request with tools
    chat_opts = Keyword.merge(opts, tools: tool_specs)

    case Openrouter.chat(client, messages, chat_opts) do
      {:ok, response} ->
        # Check if LLM wants to call tools
        if ToolCall.has_tool_calls?(response) do
          # Execute tools and continue loop
          tool_calls = ToolCall.from_response(response)

          # Add assistant's tool call message
          messages = messages ++ [response_to_message(response)]

          # Execute all tool calls
          case execute_tool_calls(tool_calls, tools, state) do
            {:ok, results} ->
              # Add tool result messages
              messages = messages ++ results

              # Continue loop
              run_loop(client, messages, tools, max_iterations, opts, %{
                state
                | iteration: state.iteration + 1
              })

            {:error, _} = error ->
              error
          end
        else
          # No tool calls, this is the final answer
          {:ok, response}
        end

      {:error, _} = error ->
        error
    end
  end

  defp execute_tool_calls(tool_calls, tools, state) do
    results =
      Enum.map(tool_calls, fn tool_call ->
        # Find the tool
        tool = find_tool(tools, tool_call.function.name)

        # Execute callback if provided
        if state.on_tool_call do
          state.on_tool_call.(tool_call)
        end

        # Parse arguments
        with {:tool, tool} when not is_nil(tool) <- {:tool, tool},
             {:ok, arguments} <- ToolCall.parse_arguments(tool_call),
             {:ok, result} <- Tool.execute(tool, arguments) do
          # Execute callback if provided
          if state.on_tool_result do
            state.on_tool_result.(tool_call, result)
          end

          ToolCall.create_result_message(tool_call, result)
        else
          {:tool, nil} ->
            Logger.error("Tool not found: #{tool_call.function.name}")

            ToolCall.create_result_message(
              tool_call,
              "Error: Tool '#{tool_call.function.name}' not found"
            )

          {:error, error} ->
            Logger.error("Tool execution failed: #{inspect(error)}")
            ToolCall.create_result_message(tool_call, "Error: #{inspect(error)}")
        end
      end)

    {:ok, results}
  end

  defp find_tool(tools, name) do
    Enum.find(tools, fn tool -> to_string(tool.name) == name end)
  end

  defp response_to_message(%Response{} = response) do
    Message.new(
      :assistant,
      response.content,
      tool_calls: response.tool_calls
    )
  end
end
