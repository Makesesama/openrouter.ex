defmodule Openrouter.PromptTemplate do
  @moduledoc """
  Prompt template management with variable substitution and composition.

  This module provides a way to define reusable prompt templates with variables,
  conditional logic, and composition capabilities for production applications.

  ## Features

  - Variable substitution with `{{variable}}` syntax
  - Conditional blocks with `{{#if variable}}...{{/if}}`
  - Default values for optional variables
  - Template validation (check for missing required variables)
  - Template composition (combine multiple templates)
  - Load templates from strings or files

  ## Examples

      # Simple template
      template = PromptTemplate.new(\"\"\"
      Hello {{name}}!
      You are {{age}} years old.
      \"\"\")

      prompt = PromptTemplate.render(template, name: "Alice", age: 25)
      # => "Hello Alice!\\nYou are 25 years old."

      # Template with defaults
      template = PromptTemplate.new(
        "Welcome {{name}}! Role: {{role}}",
        defaults: %{role: "user"}
      )

      prompt = PromptTemplate.render(template, name: "Bob")
      # => "Welcome Bob! Role: user"

      # Conditional blocks
      template = PromptTemplate.new(\"\"\"
      Hello {{name}}!
      {{#if admin}}
      You have admin access.
      {{/if}}
      \"\"\")

      prompt = PromptTemplate.render(template, name: "Alice", admin: true)
      # => "Hello Alice!\\nYou have admin access."

      # Load from file
      {:ok, template} = PromptTemplate.from_file("prompts/greeting.txt")

      # Composition
      header = PromptTemplate.new("System: {{system}}")
      body = PromptTemplate.new("User query: {{query}}")
      combined = PromptTemplate.compose([header, body], separator: "\\n\\n")
  """

  @type t :: %__MODULE__{
          template: String.t(),
          variables: [atom()],
          defaults: map(),
          metadata: map()
        }

  defstruct [:template, :variables, :defaults, :metadata]

  @doc """
  Creates a new prompt template from a string.

  ## Options

  - `:defaults` - Map of default values for optional variables
  - `:metadata` - Additional metadata (e.g., name, version, description)

  ## Examples

      template = PromptTemplate.new(
        "Hello {{name}}!",
        defaults: %{name: "Guest"}
      )
  """
  @spec new(String.t(), keyword()) :: t()
  def new(template_string, opts \\ []) when is_binary(template_string) do
    defaults = Keyword.get(opts, :defaults, %{})
    metadata = Keyword.get(opts, :metadata, %{})

    variables = extract_variables(template_string)

    %__MODULE__{
      template: template_string,
      variables: variables,
      defaults: defaults,
      metadata: metadata
    }
  end

  @doc """
  Loads a template from a file.

  ## Examples

      {:ok, template} = PromptTemplate.from_file("prompts/system.txt")
      {:ok, template} = PromptTemplate.from_file("prompts/user.txt", defaults: %{role: "user"})
  """
  @spec from_file(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, content} ->
        template = new(content, opts)
        {:ok, template}

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  @doc """
  Renders a template with the provided variables.

  Returns `{:ok, rendered}` if all required variables are provided,
  `{:error, reason}` if variables are missing.

  ## Examples

      template = PromptTemplate.new("Hello {{name}}!")
      {:ok, result} = PromptTemplate.render(template, name: "Alice")
      # => {:ok, "Hello Alice!"}

      {:error, {:missing_variables, [:name]}} = PromptTemplate.render(template, [])
  """
  @spec render(t(), keyword() | map()) :: {:ok, String.t()} | {:error, term()}
  def render(%__MODULE__{} = template, variables) do
    vars = normalize_variables(variables)
    vars_with_defaults = Map.merge(template.defaults, vars)

    case validate_variables(template, vars_with_defaults) do
      :ok ->
        rendered = do_render(template.template, vars_with_defaults)
        {:ok, rendered}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Renders a template with the provided variables, raising on error.

  ## Examples

      template = PromptTemplate.new("Hello {{name}}!")
      result = PromptTemplate.render!(template, name: "Alice")
      # => "Hello Alice!"
  """
  @spec render!(t(), keyword() | map()) :: String.t()
  def render!(%__MODULE__{} = template, variables) do
    case render(template, variables) do
      {:ok, result} -> result
      {:error, reason} -> raise "Template rendering failed: #{inspect(reason)}"
    end
  end

  @doc """
  Composes multiple templates into one.

  ## Options

  - `:separator` - String to insert between templates (default: "\\n")

  ## Examples

      t1 = PromptTemplate.new("Part 1: {{a}}")
      t2 = PromptTemplate.new("Part 2: {{b}}")

      combined = PromptTemplate.compose([t1, t2], separator: "\\n\\n")
      result = PromptTemplate.render!(combined, a: "foo", b: "bar")
      # => "Part 1: foo\\n\\nPart 2: bar"
  """
  @spec compose([t()], keyword()) :: t()
  def compose(templates, opts \\ []) when is_list(templates) do
    separator = Keyword.get(opts, :separator, "\n")

    combined_template = Enum.map_join(templates, separator, & &1.template)

    combined_variables =
      templates
      |> Enum.flat_map(& &1.variables)
      |> Enum.uniq()

    combined_defaults =
      templates
      |> Enum.map(& &1.defaults)
      |> Enum.reduce(%{}, fn defaults, acc -> Map.merge(acc, defaults) end)

    %__MODULE__{
      template: combined_template,
      variables: combined_variables,
      defaults: combined_defaults,
      metadata: %{composed: true, template_count: length(templates)}
    }
  end

  @doc """
  Validates that all required variables are provided.

  Returns `:ok` if valid, `{:error, {:missing_variables, list}}` otherwise.
  """
  @spec validate_variables(t(), map()) :: :ok | {:error, {:missing_variables, [atom()]}}
  def validate_variables(%__MODULE__{} = template, provided_vars) do
    missing =
      template.variables
      |> Enum.reject(fn var ->
        Map.has_key?(provided_vars, var) || Map.has_key?(template.defaults, var)
      end)

    if missing == [] do
      :ok
    else
      {:error, {:missing_variables, missing}}
    end
  end

  @doc """
  Returns a list of all variables used in the template.
  """
  @spec variables(t()) :: [atom()]
  def variables(%__MODULE__{} = template) do
    template.variables
  end

  @doc """
  Returns a list of required variables (those without defaults).
  """
  @spec required_variables(t()) :: [atom()]
  def required_variables(%__MODULE__{} = template) do
    Enum.reject(template.variables, fn var ->
      Map.has_key?(template.defaults, var)
    end)
  end

  ## Private Functions

  # Extract variable names from template string
  defp extract_variables(template_string) do
    # Match {{variable}} pattern
    ~r/\{\{([^}]+)\}\}/
    |> Regex.scan(template_string, capture: :all_but_first)
    |> Enum.map(fn [var_name] ->
      var_name
      |> String.trim()
      |> extract_var_name()
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.to_atom/1)
    |> Enum.uniq()
  end

  # Extract variable name, handling conditionals
  defp extract_var_name("#if " <> name), do: String.trim(name)
  defp extract_var_name("/if"), do: nil
  defp extract_var_name(name), do: String.trim(name)

  # Normalize variables to a map with atom keys
  defp normalize_variables(vars) when is_map(vars) do
    vars
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
    end)
    |> Map.new()
  end

  defp normalize_variables(vars) when is_list(vars) do
    Map.new(vars)
  end

  # Render the template with variable substitution
  defp do_render(template, vars) do
    template
    |> process_conditionals(vars)
    |> substitute_variables(vars)
  end

  # Process conditional blocks {{#if var}}...{{/if}}
  defp process_conditionals(template, vars) do
    ~r/\{\{#if\s+(\w+)\}\}(.*?)\{\{\/if\}\}/s
    |> Regex.replace(template, fn _, var_name, content ->
      var_atom = String.to_atom(var_name)

      if truthy?(Map.get(vars, var_atom)) do
        content
      else
        ""
      end
    end)
  end

  # Substitute {{variable}} with values
  defp substitute_variables(template, vars) do
    ~r/\{\{([^}]+)\}\}/
    |> Regex.replace(template, fn _, var_name ->
      var_atom =
        var_name
        |> String.trim()
        |> String.to_atom()

      case Map.get(vars, var_atom) do
        # Keep placeholder if not found
        nil -> "{{#{var_name}}}"
        value -> to_string(value)
      end
    end)
  end

  # Check if a value is truthy
  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(""), do: false
  defp truthy?([]), do: false
  defp truthy?(_), do: true
end
