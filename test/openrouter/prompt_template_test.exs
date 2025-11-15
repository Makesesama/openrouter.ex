defmodule Openrouter.PromptTemplateTest do
  use ExUnit.Case, async: true

  alias Openrouter.PromptTemplate

  describe "new/2" do
    test "creates a simple template" do
      template = PromptTemplate.new("Hello {{name}}!")

      assert template.template == "Hello {{name}}!"
      assert template.variables == [:name]
      assert template.defaults == %{}
      assert template.metadata == %{}
    end

    test "extracts multiple variables" do
      template = PromptTemplate.new("{{greeting}} {{name}}, you are {{age}} years old")

      assert :name in template.variables
      assert :greeting in template.variables
      assert :age in template.variables
      assert length(template.variables) == 3
    end

    test "handles duplicate variables" do
      template = PromptTemplate.new("{{name}} and {{name}} again")

      assert template.variables == [:name]
    end

    test "accepts default values" do
      template =
        PromptTemplate.new(
          "Hello {{name}}!",
          defaults: %{name: "Guest"}
        )

      assert template.defaults == %{name: "Guest"}
    end

    test "accepts metadata" do
      metadata = %{version: "1.0", author: "Test"}
      template = PromptTemplate.new("Test", metadata: metadata)

      assert template.metadata == metadata
    end

    test "extracts variables from conditional blocks" do
      template =
        PromptTemplate.new("""
        Hello {{name}}
        {{#if admin}}
        You are an admin
        {{/if}}
        """)

      assert :name in template.variables
      assert :admin in template.variables
    end

    test "ignores /if closing tags" do
      template = PromptTemplate.new("{{#if test}}content{{/if}}")

      # Should only extract 'test', not include nil from /if
      assert template.variables == [:test]
    end

    test "handles templates with no variables" do
      template = PromptTemplate.new("Static content with no variables")

      assert template.variables == []
    end
  end

  describe "render/2" do
    test "renders a simple template" do
      template = PromptTemplate.new("Hello {{name}}!")

      assert {:ok, "Hello Alice!"} = PromptTemplate.render(template, name: "Alice")
    end

    test "renders with multiple variables" do
      template = PromptTemplate.new("{{greeting}} {{name}}, you are {{age}}")

      {:ok, result} =
        PromptTemplate.render(template,
          greeting: "Hello",
          name: "Bob",
          age: 30
        )

      assert result == "Hello Bob, you are 30"
    end

    test "uses default values" do
      template =
        PromptTemplate.new(
          "Hello {{name}}! Role: {{role}}",
          defaults: %{role: "user"}
        )

      {:ok, result} = PromptTemplate.render(template, name: "Alice")

      assert result =~ "Role: user"
    end

    test "overrides default values" do
      template =
        PromptTemplate.new(
          "Hello {{name}}! Role: {{role}}",
          defaults: %{role: "user"}
        )

      {:ok, result} = PromptTemplate.render(template, name: "Alice", role: "admin")

      assert result =~ "Role: admin"
    end

    test "returns error for missing required variables" do
      template = PromptTemplate.new("Hello {{name}} {{age}}")

      assert {:error, {:missing_variables, missing}} =
               PromptTemplate.render(template, name: "Alice")

      assert :age in missing
    end

    test "accepts map variables" do
      template = PromptTemplate.new("Hello {{name}}!")

      {:ok, result} = PromptTemplate.render(template, %{name: "Alice"})

      assert result == "Hello Alice!"
    end

    test "accepts map with string keys" do
      template = PromptTemplate.new("Hello {{name}}!")

      {:ok, result} = PromptTemplate.render(template, %{"name" => "Alice"})

      assert result == "Hello Alice!"
    end

    test "converts non-string values to strings" do
      template = PromptTemplate.new("Age: {{age}}, Active: {{active}}")

      {:ok, result} = PromptTemplate.render(template, age: 30, active: true)

      assert result == "Age: 30, Active: true"
    end
  end

  describe "render!/2" do
    test "returns rendered string on success" do
      template = PromptTemplate.new("Hello {{name}}!")

      result = PromptTemplate.render!(template, name: "Alice")

      assert result == "Hello Alice!"
    end

    test "raises on error" do
      template = PromptTemplate.new("Hello {{name}}!")

      assert_raise RuntimeError, fn ->
        PromptTemplate.render!(template, [])
      end
    end
  end

  describe "conditional blocks" do
    test "renders content when condition is true" do
      template =
        PromptTemplate.new("""
        Hello {{name}}
        {{#if admin}}
        You have admin access
        {{/if}}
        """)

      {:ok, result} = PromptTemplate.render(template, name: "Alice", admin: true)

      assert result =~ "You have admin access"
    end

    test "omits content when condition is false" do
      template =
        PromptTemplate.new("""
        Hello {{name}}
        {{#if admin}}
        You have admin access
        {{/if}}
        """)

      {:ok, result} = PromptTemplate.render(template, name: "Alice", admin: false)

      refute result =~ "You have admin access"
    end

    test "treats nil as false" do
      template = PromptTemplate.new("{{#if value}}Yes{{/if}}")

      {:ok, result} = PromptTemplate.render(template, value: nil)

      assert result == ""
    end

    test "treats empty string as false" do
      template = PromptTemplate.new("{{#if value}}Yes{{/if}}")

      {:ok, result} = PromptTemplate.render(template, value: "")

      assert result == ""
    end

    test "treats empty list as false" do
      template = PromptTemplate.new("{{#if value}}Yes{{/if}}")

      {:ok, result} = PromptTemplate.render(template, value: [])

      assert result == ""
    end

    test "treats non-empty values as true" do
      template = PromptTemplate.new("{{#if value}}Yes{{/if}}")

      {:ok, result} = PromptTemplate.render(template, value: "something")

      assert result == "Yes"
    end

    test "handles multiple conditional blocks" do
      template =
        PromptTemplate.new("""
        {{#if a}}A is true{{/if}}
        {{#if b}}B is true{{/if}}
        {{#if c}}C is true{{/if}}
        """)

      {:ok, result} = PromptTemplate.render(template, a: true, b: false, c: true)

      assert result =~ "A is true"
      refute result =~ "B is true"
      assert result =~ "C is true"
    end

    test "handles nested variables in conditionals" do
      template =
        PromptTemplate.new("""
        {{#if premium}}
        Welcome {{name}}, Premium Member!
        {{/if}}
        """)

      {:ok, result} = PromptTemplate.render(template, premium: true, name: "Alice")

      assert result =~ "Welcome Alice, Premium Member!"
    end

    test "preserves whitespace in conditional blocks" do
      template =
        PromptTemplate.new("""
        Start
        {{#if show}}
          Indented content
        {{/if}}
        End
        """)

      {:ok, result} = PromptTemplate.render(template, show: true)

      assert result =~ "  Indented content"
    end
  end

  describe "compose/2" do
    test "combines two templates" do
      t1 = PromptTemplate.new("Part 1: {{a}}")
      t2 = PromptTemplate.new("Part 2: {{b}}")

      combined = PromptTemplate.compose([t1, t2])

      assert combined.template =~ "Part 1:"
      assert combined.template =~ "Part 2:"
    end

    test "uses default separator" do
      t1 = PromptTemplate.new("First")
      t2 = PromptTemplate.new("Second")

      combined = PromptTemplate.compose([t1, t2])

      assert combined.template == "First\nSecond"
    end

    test "uses custom separator" do
      t1 = PromptTemplate.new("First")
      t2 = PromptTemplate.new("Second")

      combined = PromptTemplate.compose([t1, t2], separator: "\n\n---\n\n")

      assert combined.template == "First\n\n---\n\nSecond"
    end

    test "merges variables from all templates" do
      t1 = PromptTemplate.new("{{a}} {{b}}")
      t2 = PromptTemplate.new("{{c}} {{d}}")

      combined = PromptTemplate.compose([t1, t2])

      assert :a in combined.variables
      assert :b in combined.variables
      assert :c in combined.variables
      assert :d in combined.variables
    end

    test "deduplicates variables" do
      t1 = PromptTemplate.new("{{name}}")
      t2 = PromptTemplate.new("{{name}}")

      combined = PromptTemplate.compose([t1, t2])

      assert Enum.count(combined.variables, &(&1 == :name)) == 1
    end

    test "merges defaults" do
      t1 = PromptTemplate.new("{{a}}", defaults: %{a: "A"})
      t2 = PromptTemplate.new("{{b}}", defaults: %{b: "B"})

      combined = PromptTemplate.compose([t1, t2])

      assert combined.defaults == %{a: "A", b: "B"}
    end

    test "later defaults override earlier ones" do
      t1 = PromptTemplate.new("{{x}}", defaults: %{x: "first"})
      t2 = PromptTemplate.new("{{x}}", defaults: %{x: "second"})

      combined = PromptTemplate.compose([t1, t2])

      assert combined.defaults[:x] == "second"
    end

    test "renders composed template" do
      t1 = PromptTemplate.new("System: {{system}}")
      t2 = PromptTemplate.new("User: {{query}}")

      combined = PromptTemplate.compose([t1, t2], separator: "\n")

      {:ok, result} =
        PromptTemplate.render(combined,
          system: "You are helpful",
          query: "Help me"
        )

      assert result == "System: You are helpful\nUser: Help me"
    end

    test "sets composition metadata" do
      t1 = PromptTemplate.new("First")
      t2 = PromptTemplate.new("Second")
      t3 = PromptTemplate.new("Third")

      combined = PromptTemplate.compose([t1, t2, t3])

      assert combined.metadata[:composed] == true
      assert combined.metadata[:template_count] == 3
    end

    test "handles empty list" do
      combined = PromptTemplate.compose([])

      assert combined.template == ""
      assert combined.variables == []
      assert combined.defaults == %{}
    end

    test "handles single template" do
      t = PromptTemplate.new("Only {{one}}")

      combined = PromptTemplate.compose([t])

      assert combined.template == "Only {{one}}"
      assert combined.variables == [:one]
    end
  end

  describe "validate_variables/2" do
    test "returns :ok when all required variables provided" do
      template = PromptTemplate.new("{{a}} {{b}}")

      assert :ok = PromptTemplate.validate_variables(template, %{a: 1, b: 2})
    end

    test "returns :ok when defaults satisfy requirements" do
      template = PromptTemplate.new("{{a}} {{b}}", defaults: %{b: "default"})

      assert :ok = PromptTemplate.validate_variables(template, %{a: 1})
    end

    test "returns error when required variables missing" do
      template = PromptTemplate.new("{{a}} {{b}} {{c}}")

      assert {:error, {:missing_variables, missing}} =
               PromptTemplate.validate_variables(template, %{a: 1})

      assert :b in missing
      assert :c in missing
    end

    test "returns :ok for template with no variables" do
      template = PromptTemplate.new("Static content")

      assert :ok = PromptTemplate.validate_variables(template, %{})
    end
  end

  describe "variables/1" do
    test "returns all variables" do
      template = PromptTemplate.new("{{a}} {{b}} {{c}}")

      vars = PromptTemplate.variables(template)

      assert length(vars) == 3
      assert :a in vars
      assert :b in vars
      assert :c in vars
    end

    test "returns empty list for static template" do
      template = PromptTemplate.new("No variables here")

      assert PromptTemplate.variables(template) == []
    end
  end

  describe "required_variables/1" do
    test "returns variables without defaults" do
      template =
        PromptTemplate.new(
          "{{a}} {{b}} {{c}}",
          defaults: %{b: "B"}
        )

      required = PromptTemplate.required_variables(template)

      assert :a in required
      assert :c in required
      refute :b in required
    end

    test "returns all variables when no defaults" do
      template = PromptTemplate.new("{{a}} {{b}}")

      required = PromptTemplate.required_variables(template)

      assert :a in required
      assert :b in required
    end

    test "returns empty list when all have defaults" do
      template =
        PromptTemplate.new(
          "{{a}} {{b}}",
          defaults: %{a: 1, b: 2}
        )

      assert PromptTemplate.required_variables(template) == []
    end
  end

  describe "from_file/2" do
    setup do
      # Create a temporary template file
      path = "/tmp/test_template_#{:rand.uniform(10000)}.txt"
      File.write!(path, "Hello {{name}} from file!")

      on_exit(fn -> File.rm(path) end)

      {:ok, path: path}
    end

    test "loads template from file", %{path: path} do
      {:ok, template} = PromptTemplate.from_file(path)

      assert template.template == "Hello {{name}} from file!"
      assert :name in template.variables
    end

    test "accepts options", %{path: path} do
      {:ok, template} =
        PromptTemplate.from_file(path,
          defaults: %{name: "World"},
          metadata: %{source: "file"}
        )

      assert template.defaults == %{name: "World"}
      assert template.metadata == %{source: "file"}
    end

    test "returns error for missing file" do
      assert {:error, {:file_error, :enoent}} =
               PromptTemplate.from_file("/nonexistent/file.txt")
    end

    test "renders template loaded from file", %{path: path} do
      {:ok, template} = PromptTemplate.from_file(path)
      {:ok, result} = PromptTemplate.render(template, name: "Alice")

      assert result == "Hello Alice from file!"
    end
  end

  describe "edge cases" do
    test "handles empty template" do
      template = PromptTemplate.new("")

      {:ok, result} = PromptTemplate.render(template, [])

      assert result == ""
    end

    test "handles template with only whitespace" do
      template = PromptTemplate.new("   \n\t  ")

      {:ok, result} = PromptTemplate.render(template, [])

      assert result == "   \n\t  "
    end

    test "handles variables with whitespace" do
      template = PromptTemplate.new("{{ name }}")

      {:ok, result} = PromptTemplate.render(template, name: "Alice")

      assert result == "Alice"
    end

    test "handles malformed conditionals gracefully" do
      template = PromptTemplate.new("{{#if test}} content")

      # Should still extract variable
      assert :test in template.variables
    end

    test "keeps placeholder for undefined optional variables" do
      template = PromptTemplate.new("Name: {{name}}, Age: {{age}}")

      # When validation is bypassed (all defaults), undefined vars keep placeholder
      # This tests the substitute_variables logic
      vars = %{name: "Alice"}

      # Direct call would show the behavior, but render validates first
      # So this tests that missing vars without defaults fail validation
      assert {:error, {:missing_variables, [:age]}} =
               PromptTemplate.render(template, vars)
    end

    test "handles special characters in variable values" do
      template = PromptTemplate.new("Message: {{msg}}")

      {:ok, result} =
        PromptTemplate.render(template,
          msg: "Hello & goodbye! <test>"
        )

      assert result == "Message: Hello & goodbye! <test>"
    end

    test "handles multiline variable values" do
      template = PromptTemplate.new("Content:\n{{text}}")

      {:ok, result} =
        PromptTemplate.render(template,
          text: "Line 1\nLine 2\nLine 3"
        )

      assert result =~ "Line 1\nLine 2\nLine 3"
    end

    test "handles unicode in templates and variables" do
      template = PromptTemplate.new("Hello {{name}}! 你好 {{chinese_name}}")

      {:ok, result} =
        PromptTemplate.render(template,
          name: "Alice",
          chinese_name: "艾丽丝"
        )

      assert result == "Hello Alice! 你好 艾丽丝"
    end
  end

  describe "complex real-world scenarios" do
    test "multi-step prompt chain" do
      step1 =
        PromptTemplate.new(
          "Extract {{entity_type}} from: {{text}}",
          defaults: %{entity_type: "entities"}
        )

      step2 = PromptTemplate.new("Analyze: {{results}}")

      chain = PromptTemplate.compose([step1, step2], separator: "\n\n")

      {:ok, result} =
        PromptTemplate.render(chain,
          text: "Apple and Google announced...",
          entity_type: "companies",
          results: "[\"Apple\", \"Google\"]"
        )

      assert result =~ "Extract companies"
      assert result =~ "Analyze: "
    end

    test "RAG template with multiple conditionals" do
      template =
        PromptTemplate.new("""
        Context: {{context}}
        Question: {{question}}
        {{#if strict}}
        Only use provided context.
        {{/if}}
        {{#if cite}}
        Include citations.
        {{/if}}
        {{#if format}}
        Format: {{format}}
        {{/if}}
        """)

      {:ok, result} =
        PromptTemplate.render(template,
          context: "Some context...",
          question: "What is X?",
          strict: true,
          cite: true,
          format: "markdown"
        )

      assert result =~ "Only use provided context"
      assert result =~ "Include citations"
      assert result =~ "Format: markdown"
    end

    test "customer support template with defaults and conditionals" do
      template =
        PromptTemplate.new(
          """
          Customer: {{customer_name}}
          Issue: {{issue}}
          {{#if urgent}}
          ⚠️ URGENT
          {{/if}}
          Agent: {{agent}}
          """,
          defaults: %{agent: "Support Team", urgent: false}
        )

      {:ok, result} =
        PromptTemplate.render(template,
          customer_name: "John",
          issue: "Billing problem",
          urgent: true
        )

      assert result =~ "John"
      assert result =~ "Billing problem"
      assert result =~ "⚠️ URGENT"
      assert result =~ "Support Team"
    end
  end
end
