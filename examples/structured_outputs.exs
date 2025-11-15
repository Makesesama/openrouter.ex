# Structured Output Examples for Openrouter.ex
#
# This file demonstrates how to extract structured data from text
# using Ecto schemas with automatic validation and retry.
#
# To run these examples:
#   export OPENROUTER_API_KEY="or-..."
#   mix run examples/structured_outputs.exs

# Example 1: Simple user extraction
defmodule UserSchema do
  use Openrouter.Schema

  embedded_schema do
    field :name, :string
    field :age, :integer
    field :email, :string
    field :city, :string
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :age, :email, :city])
    |> validate_required([:name, :age])
    |> validate_number(:age, greater_than: 0, less_than: 150)
    |> validate_format(:email, ~r/@/, message: "must be a valid email")
  end
end

IO.puts("\n=== Example 1: User Extraction ===")

text = """
John Doe is a 28-year-old software engineer living in San Francisco.
His email is john.doe@example.com and he's been coding for 10 years.
"""

case Openrouter.extract(text, schema: UserSchema, model: "openai/gpt-4") do
  {:ok, user} ->
    IO.puts("✓ Successfully extracted user:")
    IO.puts("  Name: #{user.name}")
    IO.puts("  Age: #{user.age}")
    IO.puts("  Email: #{user.email}")
    IO.puts("  City: #{user.city}")

  {:error, error} ->
    IO.puts("✗ Error: #{inspect(error)}")
end

# Example 2: Product information extraction
defmodule ProductSchema do
  use Openrouter.Schema

  embedded_schema do
    field :name, :string
    field :price, :float
    field :category, :string
    field :in_stock, :boolean
    field :features, {:array, :string}
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :price, :category, :in_stock, :features])
    |> validate_required([:name, :price, :category])
    |> validate_number(:price, greater_than: 0)
  end
end

IO.puts("\n=== Example 2: Product Extraction ===")

product_text = """
Introducing the UltraBook Pro - a premium laptop priced at $1,299.99.
This device features a stunning 4K display, 16GB RAM, and 512GB SSD.
It's currently in stock and belongs to the Electronics category.
Key features include: long battery life, lightweight design, and fast performance.
"""

case Openrouter.extract(product_text, schema: ProductSchema, model: "anthropic/claude-sonnet-4-0") do
  {:ok, product} ->
    IO.puts("✓ Successfully extracted product:")
    IO.puts("  Name: #{product.name}")
    IO.puts("  Price: $#{product.price}")
    IO.puts("  Category: #{product.category}")
    IO.puts("  In Stock: #{product.in_stock}")
    IO.puts("  Features: #{Enum.join(product.features || [], ", ")}")

  {:error, error} ->
    IO.puts("✗ Error: #{inspect(error)}")
end

# Example 3: Complex nested structure
defmodule AddressSchema do
  use Openrouter.Schema

  embedded_schema do
    field :street, :string
    field :city, :string
    field :state, :string
    field :zip_code, :string
  end
end

defmodule CompanySchema do
  use Openrouter.Schema

  embedded_schema do
    field :name, :string
    field :founded_year, :integer
    field :employee_count, :integer
    embeds_one :headquarters, AddressSchema
    field :industries, {:array, :string}
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :founded_year, :employee_count, :industries])
    |> cast_embed(:headquarters, with: &AddressSchema.changeset/2)
    |> validate_required([:name, :founded_year])
    |> validate_number(:founded_year, greater_than: 1800, less_than: 2100)
  end
end

IO.puts("\n=== Example 3: Company Extraction (Nested) ===")

company_text = """
TechCorp Inc. was founded in 2010 and currently employs approximately 5000 people.
The company's headquarters is located at 123 Tech Street, San Francisco, CA 94105.
TechCorp operates in the software development and cloud computing industries.
"""

case Openrouter.extract(company_text, schema: CompanySchema, model: "openai/gpt-4") do
  {:ok, company} ->
    IO.puts("✓ Successfully extracted company:")
    IO.puts("  Name: #{company.name}")
    IO.puts("  Founded: #{company.founded_year}")
    IO.puts("  Employees: #{company.employee_count}")

    if company.headquarters do
      IO.puts("  HQ: #{company.headquarters.city}, #{company.headquarters.state}")
    end

    IO.puts("  Industries: #{Enum.join(company.industries || [], ", ")}")

  {:error, error} ->
    IO.puts("✗ Error: #{inspect(error)}")
end

# Example 4: Using raw JSON schema
IO.puts("\n=== Example 4: Raw JSON Schema ===")

recipe_schema = %{
  type: "object",
  properties: %{
    name: %{type: "string"},
    prep_time_minutes: %{type: "integer"},
    difficulty: %{type: "string", enum: ["easy", "medium", "hard"]},
    ingredients: %{
      type: "array",
      items: %{type: "string"}
    },
    steps: %{
      type: "array",
      items: %{type: "string"}
    }
  },
  required: ["name", "ingredients", "steps"]
}

recipe_text = """
Here's my favorite chocolate chip cookie recipe:
Mix butter and sugar, add eggs and vanilla, combine with flour and baking soda.
Fold in chocolate chips. Bake at 350°F for 12 minutes.
Prep time is about 15 minutes. This is an easy recipe perfect for beginners.
"""

case Openrouter.extract(recipe_text, json_schema: recipe_schema, model: "openai/gpt-4") do
  {:ok, recipe} ->
    IO.puts("✓ Successfully extracted recipe:")
    IO.puts("  Name: #{recipe["name"]}")
    IO.puts("  Prep Time: #{recipe["prep_time_minutes"]} minutes")
    IO.puts("  Difficulty: #{recipe["difficulty"]}")
    IO.puts("  Ingredients: #{length(recipe["ingredients"] || [])} items")
    IO.puts("  Steps: #{length(recipe["steps"] || [])} steps")

  {:error, error} ->
    IO.puts("✗ Error: #{inspect(error)}")
end

# Example 5: Error handling and validation
IO.puts("\n=== Example 5: Validation with Retry ===")

defmodule StrictUserSchema do
  use Openrouter.Schema

  embedded_schema do
    field :email, :string
    field :age, :integer
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:email, :age])
    |> validate_required([:email, :age])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_number(:age, greater_than_or_equal_to: 18, less_than: 120)
  end
end

# This text is intentionally vague to test retry logic
vague_text = "Contact info: alice at example dot com, she's 25"

IO.puts("Extracting with automatic retry on validation errors...")

case Openrouter.extract(vague_text,
       schema: StrictUserSchema,
       model: "openai/gpt-4",
       max_retries: 3
     ) do
  {:ok, user} ->
    IO.puts("✓ Successfully extracted (after potential retries):")
    IO.puts("  Email: #{user.email}")
    IO.puts("  Age: #{user.age}")

  {:error, %Ecto.Changeset{} = changeset} ->
    IO.puts("✗ Validation failed after all retries")
    IO.puts("  Errors: #{Openrouter.Schema.format_errors(changeset)}")

  {:error, error} ->
    IO.puts("✗ Error: #{inspect(error)}")
end

IO.puts("\n=== All Examples Complete ===")
