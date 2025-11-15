# Prompt Template Examples for Openrouter.ex
#
# This file demonstrates how to use prompt templates for reusable,
# production-ready prompt engineering with variable substitution and composition.
#
# To run these examples:
#   export OPENROUTER_API_KEY="or-..."
#   mix run examples/prompt_templates.exs

alias Openrouter.PromptTemplate

IO.puts("\n=== Example 1: Simple Variable Substitution ===")

template = PromptTemplate.new("""
Hello {{name}}!
You are {{age}} years old and work as a {{job}}.
""")

{:ok, rendered} = PromptTemplate.render(template, name: "Alice", age: 30, job: "engineer")
IO.puts(rendered)

IO.puts("\n=== Example 2: Templates with Default Values ===")

greeting_template = PromptTemplate.new(
  "Welcome {{name}}! Your role is: {{role}}",
  defaults: %{role: "user"}
)

# Uses default role
{:ok, result1} = PromptTemplate.render(greeting_template, name: "Bob")
IO.puts(result1)

# Overrides default role
{:ok, result2} = PromptTemplate.render(greeting_template, name: "Carol", role: "admin")
IO.puts(result2)

IO.puts("\n=== Example 3: Conditional Blocks ===")

status_template = PromptTemplate.new("""
User: {{username}}
{{#if premium}}
Status: Premium Member
Features: Advanced Analytics, Priority Support
{{/if}}
{{#if trial}}
Status: Trial Period ({{days_left}} days remaining)
{{/if}}
""")

{:ok, premium_msg} = PromptTemplate.render(status_template,
  username: "alice",
  premium: true
)
IO.puts("Premium User:")
IO.puts(premium_msg)

{:ok, trial_msg} = PromptTemplate.render(status_template,
  username: "bob",
  trial: true,
  days_left: 7
)
IO.puts("\nTrial User:")
IO.puts(trial_msg)

IO.puts("\n=== Example 4: Template Composition ===")

system_template = PromptTemplate.new("""
You are a {{role}} with expertise in {{domain}}.
Your responses should be {{style}}.
""")

user_template = PromptTemplate.new("""
User Query: {{query}}

Context: {{context}}
""")

combined = PromptTemplate.compose([system_template, user_template], separator: "\n")

{:ok, full_prompt} = PromptTemplate.render(combined,
  role: "helpful assistant",
  domain: "software engineering",
  style: "concise and technical",
  query: "How do I optimize database queries?",
  context: "Working with PostgreSQL on a high-traffic application"
)

IO.puts(full_prompt)

IO.puts("\n=== Example 5: Production RAG Template ===")

rag_template = PromptTemplate.new("""
SYSTEM CONTEXT:
You are an AI assistant that answers questions based on provided documentation.

RETRIEVED DOCUMENTS:
{{documents}}

USER QUESTION:
{{question}}

INSTRUCTIONS:
{{#if cite_sources}}
- Cite the source document for each piece of information
- Use [Doc N] format for citations
{{/if}}
{{#if strict_mode}}
- Only answer based on the provided documents
- If the answer is not in the documents, say "I don't have enough information"
{{/if}}

Please provide a comprehensive answer:
""",
  defaults: %{cite_sources: true, strict_mode: false}
)

{:ok, rag_prompt} = PromptTemplate.render(rag_template,
  documents: """
  [Doc 1] Elixir is a functional programming language that runs on the BEAM VM.
  [Doc 2] GenServer is an OTP behavior for implementing stateful processes.
  [Doc 3] Phoenix is a web framework written in Elixir.
  """,
  question: "What is Elixir and what frameworks are available?",
  cite_sources: true,
  strict_mode: true
)

IO.puts(rag_prompt)

IO.puts("\n=== Example 6: Using Templates with Chat API ===")

chat_template = PromptTemplate.new("""
Analyze the following code and provide suggestions for improvement.

Language: {{language}}
Code:
```
{{code}}
```

Focus on:
{{#if performance}}
- Performance optimizations
{{/if}}
{{#if readability}}
- Code readability and style
{{/if}}
{{#if security}}
- Security best practices
{{/if}}
""",
  defaults: %{performance: true, readability: true, security: false}
)

{:ok, analysis_prompt} = PromptTemplate.render(chat_template,
  language: "Elixir",
  code: """
  def process_users(users) do
    Enum.map(users, fn user ->
      # Process each user
      {:ok, user}
    end)
  end
  """,
  performance: true,
  readability: true,
  security: true
)

IO.puts("Sending to LLM:")
IO.puts(analysis_prompt)

# Use with actual API call
case Openrouter.chat([
  %{role: "user", content: analysis_prompt}
], model: "anthropic/claude-3.5-sonnet") do
  {:ok, response} ->
    IO.puts("\nLLM Response:")
    IO.puts(response.choices |> List.first() |> Map.get(:message) |> Map.get(:content))
  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\n=== Example 7: Loading Templates from Files ===")

# Create a temporary template file
template_content = """
Customer Support Response Template

Customer: {{customer_name}}
Issue: {{issue_type}}
Severity: {{severity}}

{{#if urgent}}
⚠️  URGENT - Requires immediate attention
{{/if}}

Response:
Dear {{customer_name}},

Thank you for contacting us about {{issue_type}}.
{{resolution}}

Best regards,
{{agent_name}}
"""

File.write!("/tmp/support_template.txt", template_content)

{:ok, support_template} = PromptTemplate.from_file(
  "/tmp/support_template.txt",
  defaults: %{agent_name: "Support Team", severity: "medium"}
)

{:ok, support_msg} = PromptTemplate.render(support_template,
  customer_name: "John Smith",
  issue_type: "billing inquiry",
  urgent: false,
  resolution: "We've reviewed your account and will process the refund within 3-5 business days."
)

IO.puts(support_msg)

# Clean up
File.rm("/tmp/support_template.txt")

IO.puts("\n=== Example 8: Validation and Error Handling ===")

strict_template = PromptTemplate.new("""
Translate the following text from {{source_lang}} to {{target_lang}}:

{{text}}

Style: {{style}}
""")

IO.puts("Template requires: #{inspect(PromptTemplate.required_variables(strict_template))}")

# This will fail - missing required variables
case PromptTemplate.render(strict_template, text: "Hello world") do
  {:ok, _result} ->
    IO.puts("Success!")
  {:error, {:missing_variables, missing}} ->
    IO.puts("❌ Error: Missing required variables: #{inspect(missing)}")
end

# This will succeed - all variables provided
case PromptTemplate.render(strict_template,
  source_lang: "English",
  target_lang: "Spanish",
  text: "Hello world",
  style: "formal"
) do
  {:ok, result} ->
    IO.puts("✓ Success!")
    IO.puts(result)
  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\n=== Example 9: Multi-Step Prompt Chains ===")

# Step 1: Extract entities
extraction_template = PromptTemplate.new("""
Extract all {{entity_type}} from the following text:

{{text}}

Output format: JSON array
""")

# Step 2: Analyze entities
analysis_template = PromptTemplate.new("""
Analyze the following {{entity_type}}:

{{entities}}

Provide:
{{#if sentiment}}
- Sentiment analysis
{{/if}}
{{#if relationships}}
- Relationship mapping
{{/if}}
{{#if summary}}
- Executive summary
{{/if}}
""")

{:ok, extract_prompt} = PromptTemplate.render(extraction_template,
  entity_type: "company names",
  text: "Apple and Microsoft announced a partnership. Google responded positively."
)

IO.puts("Step 1 - Extraction:")
IO.puts(extract_prompt)

{:ok, analyze_prompt} = PromptTemplate.render(analysis_template,
  entity_type: "companies",
  entities: "[\"Apple\", \"Microsoft\", \"Google\"]",
  sentiment: true,
  relationships: true,
  summary: true
)

IO.puts("\nStep 2 - Analysis:")
IO.puts(analyze_prompt)

IO.puts("\n=== Example 10: Metadata and Template Management ===")

versioned_template = PromptTemplate.new(
  "Process {{input}} with {{algorithm}}",
  defaults: %{algorithm: "standard"},
  metadata: %{
    name: "data_processor",
    version: "2.1.0",
    author: "Data Team",
    description: "Standard data processing template",
    created_at: DateTime.utc_now()
  }
)

IO.puts("Template Metadata:")
IO.inspect(versioned_template.metadata, pretty: true)

IO.puts("\nTemplate Variables:")
IO.inspect(PromptTemplate.variables(versioned_template))

IO.puts("\nRequired Variables:")
IO.inspect(PromptTemplate.required_variables(versioned_template))

IO.puts("\n=== All Examples Complete ===")
