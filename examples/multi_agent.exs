#!/usr/bin/env elixir
#
# Multi-Agent Collaboration Example
#
# This example demonstrates patterns for coordinating multiple AI agents:
# - Sequential agent workflows
# - Parallel agent execution
# - Hierarchical agent systems
# - Agent specialization
# - Inter-agent communication
#
# Run with: mix run examples/multi_agent.exs

Mix.install([{:openrouter, path: "."}])

require Logger

IO.puts("\n=== Multi-Agent Collaboration Example ===\n")

# ============================================================================
# Example 1: Sequential Agent Pipeline
# ============================================================================

IO.puts("1. Sequential Agent Pipeline")
IO.puts("   Agents process data in sequence\n")

# Agent 1: Researcher
research_agent_result =
  Openrouter.chat(
    "Research the key features of Elixir programming language. List 3 main features.",
    model: "openai/gpt-3.5-turbo",
    system: "You are a research agent. Provide factual, concise information."
  )

{:ok, research} = research_agent_result
IO.puts("Research Agent: #{research.content}\n")

# Agent 2: Analyzer (uses research output)
analysis_prompt = """
Analyze the following information and identify the most important feature:

#{research.content}

Provide a brief analysis of why it's most important.
"""

{:ok, analysis} =
  Openrouter.chat(
    analysis_prompt,
    model: "openai/gpt-3.5-turbo",
    system: "You are an analysis agent. Provide deep insights."
  )

IO.puts("Analysis Agent: #{analysis.content}\n")

# Agent 3: Writer (creates final output)
writer_prompt = """
Write a one-paragraph summary based on this analysis:

#{analysis.content}

Make it engaging and accessible.
"""

{:ok, final_output} =
  Openrouter.chat(
    writer_prompt,
    model: "openai/gpt-3.5-turbo",
    system: "You are a writing agent. Create clear, engaging content."
  )

IO.puts("Writer Agent: #{final_output.content}\n")

# ============================================================================
# Example 2: Parallel Agent Execution
# ============================================================================

IO.puts("2. Parallel Agent Execution")
IO.puts("   Multiple agents work simultaneously\n")

topic = "Phoenix Framework"

# Run multiple agents in parallel
tasks = [
  Task.async(fn ->
    {:ok, response} =
      Openrouter.chat(
        "What are the main features of #{topic}? List 3 key features.",
        model: "openai/gpt-3.5-turbo",
        system: "You are a features specialist."
      )

    {:features, response.content}
  end),
  Task.async(fn ->
    {:ok, response} =
      Openrouter.chat(
        "What are the pros and cons of #{topic}?",
        model: "openai/gpt-3.5-turbo",
        system: "You are a critical analysis specialist."
      )

    {:analysis, response.content}
  end),
  Task.async(fn ->
    {:ok, response} =
      Openrouter.chat(
        "Provide a beginner-friendly explanation of #{topic}.",
        model: "openai/gpt-3.5-turbo",
        system: "You are an education specialist."
      )

    {:explanation, response.content}
  end)
]

# Collect results
results = Task.await_many(tasks, 30_000)

IO.puts("Features Agent:")
{:features, features} = Enum.find(results, fn {type, _} -> type == :features end)
IO.puts(features)

IO.puts("\nAnalysis Agent:")
{:analysis, analysis} = Enum.find(results, fn {type, _} -> type == :analysis end)
IO.puts(analysis)

IO.puts("\nExplanation Agent:")
{:explanation, explanation} = Enum.find(results, fn {type, _} -> type == :explanation end)
IO.puts(explanation)
IO.puts("")

# ============================================================================
# Example 3: Supervisor Agent (Hierarchical System)
# ============================================================================

IO.puts("3. Hierarchical Agent System")
IO.puts("   Supervisor coordinates specialist agents\n")

defmodule AgentCoordinator do
  @doc """
  Coordinates multiple specialist agents to complete a complex task
  """
  def coordinate(task_description) do
    # Supervisor agent plans the work
    planning_prompt = """
    You are a supervisor agent. Break down this task into subtasks for specialist agents:

    Task: #{task_description}

    List 2-3 specific subtasks that different specialists should handle.
    Format: One subtask per line, brief and actionable.
    """

    {:ok, plan} =
      Openrouter.chat(
        planning_prompt,
        model: "openai/gpt-3.5-turbo",
        system: "You are a project coordinator. Create clear, actionable plans."
      )

    IO.puts("Supervisor Agent Plan:")
    IO.puts(plan.content)
    IO.puts("")

    # Parse subtasks (simplified - in production use structured outputs)
    subtasks =
      plan.content
      |> String.split("\n")
      |> Enum.filter(&(String.length(&1) > 10))
      |> Enum.take(2)

    # Assign to specialist agents
    specialist_results =
      Enum.map(subtasks, fn subtask ->
        {:ok, response} =
          Openrouter.chat(
            subtask,
            model: "openai/gpt-3.5-turbo",
            system: "You are a specialist agent. Provide detailed, expert responses."
          )

        {subtask, response.content}
      end)

    # Supervisor synthesizes results
    synthesis_prompt = """
    Synthesize these specialist reports into a cohesive summary:

    #{Enum.map_join(specialist_results, "\n\n", fn {task, result} -> "Task: #{task}\nResult: #{result}" end)}

    Provide a brief, integrated summary.
    """

    {:ok, synthesis} =
      Openrouter.chat(
        synthesis_prompt,
        model: "openai/gpt-3.5-turbo",
        system: "You are a supervisor. Synthesize information clearly."
      )

    synthesis.content
  end
end

result = AgentCoordinator.coordinate("Explain how to build a real-time chat app with Phoenix")
IO.puts("Final Synthesis:")
IO.puts(result)
IO.puts("")

# ============================================================================
# Example 4: Specialized Agent Roles with Tools
# ============================================================================

IO.puts("4. Specialized Agents with Tools")
IO.puts("   Different agents with different capabilities\n")

# Calculator Agent
calculator_tool =
  Openrouter.Tool.new(
    :calculate,
    "Perform arithmetic",
    fn %{expression: expr} ->
      # Simple evaluation (use Code.eval_string carefully in production!)
      try do
        {result, _} = Code.eval_string(expr)
        {:ok, result}
      rescue
        _ -> {:error, "Invalid expression"}
      end
    end,
    parameters: %{
      expression: [type: :string, required: true, description: "Math expression like '5 + 3'"]
    }
  )

# Database Agent (simulated)
database_tool =
  Openrouter.Tool.new(
    :query_database,
    "Query user database",
    fn %{query: _query} ->
      # Simulated database
      {:ok, "User data: Alice (age: 30), Bob (age: 25)"}
    end,
    parameters: %{
      query: [type: :string, required: true]
    }
  )

# Web Agent (simulated)
web_tool =
  Openrouter.Tool.new(
    :fetch_url,
    "Fetch web content",
    fn %{url: url} ->
      {:ok, "Content from #{url}: Latest news about technology..."}
    end,
    parameters: %{
      url: [type: :string, required: true]
    }
  )

# Create specialized agents
defmodule SpecializedAgents do
  def math_agent(query) do
    Openrouter.Agent.run(
      query,
      model: "openai/gpt-3.5-turbo",
      tools: [
        Openrouter.Tool.new(
          :calculate,
          "Perform arithmetic",
          fn %{expression: expr} ->
            try do
              {result, _} = Code.eval_string(expr)
              {:ok, result}
            rescue
              _ -> {:error, "Invalid expression"}
            end
          end,
          parameters: %{expression: [type: :string, required: true]}
        )
      ],
      system: "You are a math specialist. Use the calculator for computations."
    )
  end

  def data_agent(query) do
    Openrouter.Agent.run(
      query,
      model: "openai/gpt-3.5-turbo",
      tools: [
        Openrouter.Tool.new(
          :query_database,
          "Query database",
          fn %{query: _} -> {:ok, "User data: Alice (age: 30), Bob (age: 25)"} end,
          parameters: %{query: [type: :string, required: true]}
        )
      ],
      system: "You are a data specialist. Use database queries to answer questions."
    )
  end

  def web_agent(query) do
    Openrouter.Agent.run(
      query,
      model: "openai/gpt-3.5-turbo",
      tools: [
        Openrouter.Tool.new(
          :fetch_url,
          "Fetch web content",
          fn %{url: url} -> {:ok, "Content from #{url}: Latest news..."} end,
          parameters: %{url: [type: :string, required: true]}
        )
      ],
      system: "You are a web research specialist. Fetch and summarize web content."
    )
  end
end

{:ok, math_result} = SpecializedAgents.math_agent("What is 15 * 8 + 120?")
IO.puts("Math Agent: #{math_result.content}")

{:ok, data_result} = SpecializedAgents.data_agent("How many users do we have?")
IO.puts("Data Agent: #{data_result.content}\n")

# ============================================================================
# Example 5: Agent Communication via Shared Context
# ============================================================================

IO.puts("5. Agent Communication via RunContext")
IO.puts("   Agents share information through context\n")

defmodule SharedContext do
  defstruct [:findings, :current_agent, :task_queue]
end

# Agent 1: Researcher
research_tool =
  Openrouter.Tool.new(
    :record_finding,
    "Record research finding",
    fn ctx, %{finding: finding} ->
      # Add finding to shared context
      IO.puts("  [Research Agent] Recording: #{finding}")
      {:ok, "Finding recorded"}
    end,
    parameters: %{
      finding: [type: :string, required: true]
    },
    context_aware: true
  )

ctx = %SharedContext{findings: [], current_agent: "research", task_queue: []}

{:ok, _result} =
  Openrouter.Agent.run(
    "Research Elixir's concurrency model and record a key finding",
    model: "openai/gpt-3.5-turbo",
    tools: [research_tool],
    deps: ctx,
    system: "You are a research agent. Record important findings."
  )

IO.puts("")

# ============================================================================
# Example 6: Consensus Among Multiple Agents
# ============================================================================

IO.puts("6. Multi-Agent Consensus")
IO.puts("   Multiple agents vote on decisions\n")

defmodule ConsensusSystem do
  def get_consensus(question, agent_count \\ 3) do
    # Ask multiple agents
    tasks =
      Enum.map(1..agent_count, fn i ->
        Task.async(fn ->
          {:ok, response} =
            Openrouter.chat(
              "#{question}\n\nAnswer with 'Yes' or 'No' and a brief reason.",
              model: "openai/gpt-3.5-turbo",
              system: "You are agent #{i}. Provide your independent assessment.",
              temperature: 0.7
            )

          {i, response.content}
        end)
      end)

    results = Task.await_many(tasks, 30_000)

    # Display individual responses
    Enum.each(results, fn {i, response} ->
      IO.puts("Agent #{i}: #{response}")
    end)

    # Analyze consensus
    yes_count =
      results
      |> Enum.count(fn {_, response} ->
        String.downcase(response) =~ "yes"
      end)

    no_count = length(results) - yes_count

    consensus = if yes_count > no_count, do: "Yes", else: "No"
    confidence = max(yes_count, no_count) / length(results) * 100

    IO.puts("\nConsensus: #{consensus} (#{round(confidence)}% agreement)")

    {consensus, confidence}
  end
end

question = "Is Elixir a good choice for building web applications?"
ConsensusSystem.get_consensus(question, 3)
IO.puts("")

# ============================================================================
# Example 7: Agent Workflow with State Machine
# ============================================================================

IO.puts("7. Agent Workflow State Machine")
IO.puts("   Agents follow a defined workflow\n")

defmodule WorkflowAgent do
  @states [:planning, :research, :analysis, :synthesis, :review, :complete]

  def run_workflow(task) do
    execute_state(:planning, task, %{results: %{}})
  end

  defp execute_state(:planning, task, state) do
    IO.puts("[Planning] Creating plan for: #{task}")
    plan = "1. Research the topic\n2. Analyze findings\n3. Synthesize results"

    state = put_in(state, [:results, :plan], plan)
    execute_state(:research, task, state)
  end

  defp execute_state(:research, task, state) do
    IO.puts("[Research] Gathering information...")

    {:ok, research} =
      Openrouter.chat(
        "Research: #{task}. Provide 2 key facts.",
        model: "openai/gpt-3.5-turbo"
      )

    state = put_in(state, [:results, :research], research.content)
    execute_state(:analysis, task, state)
  end

  defp execute_state(:analysis, task, state) do
    IO.puts("[Analysis] Analyzing findings...")

    research = get_in(state, [:results, :research])

    {:ok, analysis} =
      Openrouter.chat(
        "Analyze: #{research}",
        model: "openai/gpt-3.5-turbo"
      )

    state = put_in(state, [:results, :analysis], analysis.content)
    execute_state(:synthesis, task, state)
  end

  defp execute_state(:synthesis, _task, state) do
    IO.puts("[Synthesis] Creating final output...")

    analysis = get_in(state, [:results, :analysis])

    {:ok, synthesis} =
      Openrouter.chat(
        "Synthesize into one paragraph: #{analysis}",
        model: "openai/gpt-3.5-turbo"
      )

    state = put_in(state, [:results, :synthesis], synthesis.content)
    execute_state(:complete, nil, state)
  end

  defp execute_state(:complete, _task, state) do
    IO.puts("[Complete] Workflow finished!\n")
    get_in(state, [:results, :synthesis])
  end
end

result = WorkflowAgent.run_workflow("Elixir's supervision trees")
IO.puts("Final Result: #{result}\n")

# ============================================================================
# Example 8: Production Multi-Agent Patterns
# ============================================================================

IO.puts("8. Production Multi-Agent Patterns\n")

IO.puts("Common Patterns:")

IO.puts("\n1. Map-Reduce Pattern:")
IO.puts("   - Split task into subtasks (map)")
IO.puts("   - Process in parallel with agents")
IO.puts("   - Combine results (reduce)")
IO.puts("   - Use: Large-scale analysis, batch processing")

IO.puts("\n2. Pipeline Pattern:")
IO.puts("   - Sequential agent stages")
IO.puts("   - Each agent specializes in one step")
IO.puts("   - Output feeds into next agent")
IO.puts("   - Use: Content creation, data processing")

IO.puts("\n3. Coordinator Pattern:")
IO.puts("   - Supervisor agent manages specialists")
IO.puts("   - Dynamic task assignment")
IO.puts("   - Result aggregation")
IO.puts("   - Use: Complex research, project management")

IO.puts("\n4. Consensus Pattern:")
IO.puts("   - Multiple agents evaluate independently")
IO.puts("   - Vote or average results")
IO.puts("   - Reduces individual bias")
IO.puts("   - Use: Decision making, fact checking")

IO.puts("\n5. Debate Pattern:")
IO.puts("   - Agents argue different positions")
IO.puts("   - Iterative refinement")
IO.puts("   - Improves reasoning quality")
IO.puts("   - Use: Critical analysis, strategy")

IO.puts("\n6. Specialization Pattern:")
IO.puts("   - Each agent has unique tools/capabilities")
IO.puts("   - Route queries to appropriate specialist")
IO.puts("   - Combine specialized knowledge")
IO.puts("   - Use: Expert systems, technical support")

IO.puts("\nBest Practices:")
IO.puts("- Define clear agent responsibilities")
IO.puts("- Use RunContext for shared state")
IO.puts("- Implement timeouts for reliability")
IO.puts("- Log agent interactions for debugging")
IO.puts("- Use structured outputs for agent communication")
IO.puts("- Implement error recovery strategies")
IO.puts("- Monitor costs (multiple LLM calls)")
IO.puts("- Cache agent results when possible")
IO.puts("- Use ConversationServer for stateful agents")
IO.puts("- Leverage OTP supervision for fault tolerance")

IO.puts("")

IO.puts("=== Multi-Agent Example Complete ===\n")
