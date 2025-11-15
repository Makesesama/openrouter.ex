#!/usr/bin/env elixir
#
# Nested Schemas Example
#
# This example demonstrates extracting complex hierarchical data
# using nested Ecto schemas with embeds_one and embeds_many.
#
# Run with: mix run examples/nested_schemas.exs

Mix.install([{:openrouter, path: "."}])

require Logger

IO.puts("\n=== Nested Schemas Example ===\n")

# ============================================================================
# Example 1: Simple Nested Schema (embeds_one)
# ============================================================================

IO.puts("1. Simple Nested Schema (embeds_one)")
IO.puts("   Extract person with address\n")

defmodule AddressSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:street, :string)
    field(:city, :string)
    field(:state, :string)
    field(:country, :string)
    field(:zip_code, :string)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:street, :city, :state, :country, :zip_code])
    |> validate_required([:city, :country])
  end
end

defmodule PersonSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:name, :string)
    field(:age, :integer)
    field(:email, :string)
    embeds_one(:address, AddressSchema)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :age, :email])
    |> cast_embed(:address, required: true)
    |> validate_required([:name])
  end
end

text = """
John Doe is 35 years old. His email is john@example.com.
He lives at 123 Main Street, San Francisco, California, USA, 94102.
"""

{:ok, person} =
  Openrouter.extract(
    text,
    schema: PersonSchema,
    model: "openai/gpt-3.5-turbo"
  )

IO.puts("Extracted Person:")
IO.puts("  Name: #{person.name}")
IO.puts("  Age: #{person.age}")
IO.puts("  Email: #{person.email}")
IO.puts("  Address:")
IO.puts("    Street: #{person.address.street}")
IO.puts("    City: #{person.address.city}")
IO.puts("    State: #{person.address.state}")
IO.puts("    Country: #{person.address.country}")
IO.puts("    Zip: #{person.address.zip_code}\n")

# ============================================================================
# Example 2: Array of Nested Objects (embeds_many)
# ============================================================================

IO.puts("2. Array of Nested Objects (embeds_many)")
IO.puts("   Extract person with multiple phone numbers\n")

defmodule PhoneNumberSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:type, :string)
    field(:number, :string)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:type, :number])
    |> validate_required([:type, :number])
    |> validate_inclusion(:type, ["mobile", "home", "work"])
  end
end

defmodule ContactSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:name, :string)
    embeds_many(:phone_numbers, PhoneNumberSchema)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name])
    |> cast_embed(:phone_numbers, required: true)
    |> validate_required([:name])
  end
end

text = """
Contact: Alice Smith
Phone numbers:
- Mobile: +1-555-123-4567
- Home: +1-555-987-6543
- Work: +1-555-111-2222
"""

{:ok, contact} =
  Openrouter.extract(
    text,
    schema: ContactSchema,
    model: "openai/gpt-3.5-turbo"
  )

IO.puts("Extracted Contact:")
IO.puts("  Name: #{contact.name}")
IO.puts("  Phone Numbers:")

Enum.each(contact.phone_numbers, fn phone ->
  IO.puts("    #{phone.type}: #{phone.number}")
end)

IO.puts("")

# ============================================================================
# Example 3: Deeply Nested Schema
# ============================================================================

IO.puts("3. Deeply Nested Schema")
IO.puts("   Extract company with departments and employees\n")

defmodule EmployeeSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:name, :string)
    field(:title, :string)
    field(:email, :string)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :title, :email])
    |> validate_required([:name, :title])
  end
end

defmodule DepartmentSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:name, :string)
    field(:budget, :float)
    embeds_many(:employees, EmployeeSchema)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :budget])
    |> cast_embed(:employees)
    |> validate_required([:name])
  end
end

defmodule CompanySchema do
  use Openrouter.Schema

  embedded_schema do
    field(:name, :string)
    field(:founded, :integer)
    embeds_many(:departments, DepartmentSchema)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :founded])
    |> cast_embed(:departments)
    |> validate_required([:name])
  end
end

text = """
Company: TechCorp, founded in 2010

Departments:
1. Engineering
   Budget: $2,000,000
   Employees:
   - Alice Johnson, Senior Engineer, alice@techcorp.com
   - Bob Smith, Junior Engineer, bob@techcorp.com

2. Marketing
   Budget: $500,000
   Employees:
   - Carol Davis, Marketing Manager, carol@techcorp.com
"""

{:ok, company} =
  Openrouter.extract(
    text,
    schema: CompanySchema,
    model: "openai/gpt-4"
  )

IO.puts("Extracted Company:")
IO.puts("  Name: #{company.name}")
IO.puts("  Founded: #{company.founded}")
IO.puts("  Departments:")

Enum.each(company.departments, fn dept ->
  IO.puts("    #{dept.name} (Budget: $#{dept.budget})")
  IO.puts("      Employees:")

  Enum.each(dept.employees, fn emp ->
    IO.puts("        - #{emp.name}, #{emp.title}")
  end)
end)

IO.puts("")

# ============================================================================
# Example 4: Complex E-commerce Order
# ============================================================================

IO.puts("4. Complex E-commerce Order")
IO.puts("   Extract order with items and shipping address\n")

defmodule OrderItemSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:product_name, :string)
    field(:quantity, :integer)
    field(:price, :float)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:product_name, :quantity, :price])
    |> validate_required([:product_name, :quantity, :price])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:price, greater_than: 0)
  end
end

defmodule ShippingAddressSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:recipient, :string)
    field(:street, :string)
    field(:city, :string)
    field(:zip_code, :string)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:recipient, :street, :city, :zip_code])
    |> validate_required([:recipient, :city])
  end
end

defmodule OrderSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:order_id, :string)
    field(:order_date, :string)
    field(:total_amount, :float)
    embeds_many(:items, OrderItemSchema)
    embeds_one(:shipping_address, ShippingAddressSchema)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:order_id, :order_date, :total_amount])
    |> cast_embed(:items, required: true)
    |> cast_embed(:shipping_address, required: true)
    |> validate_required([:order_id])
  end
end

text = """
Order #ORD-12345
Date: 2025-01-15
Total: $247.97

Items:
- Elixir Programming Book, Quantity: 2, Price: $49.99 each
- Phoenix Framework Guide, Quantity: 1, Price: $59.99
- Ecto Best Practices, Quantity: 3, Price: $29.33 each

Ship to:
Sarah Williams
456 Oak Avenue
Portland, OR 97201
"""

{:ok, order} =
  Openrouter.extract(
    text,
    schema: OrderSchema,
    model: "openai/gpt-4"
  )

IO.puts("Extracted Order:")
IO.puts("  Order ID: #{order.order_id}")
IO.puts("  Date: #{order.order_date}")
IO.puts("  Total: $#{order.total_amount}")
IO.puts("  Items:")

Enum.each(order.items, fn item ->
  IO.puts("    - #{item.product_name} x#{item.quantity} @ $#{item.price}")
end)

IO.puts("  Shipping Address:")
IO.puts("    #{order.shipping_address.recipient}")
IO.puts("    #{order.shipping_address.street}")
IO.puts("    #{order.shipping_address.city}, #{order.shipping_address.zip_code}")

IO.puts("")

# ============================================================================
# Example 5: Resume/CV Parsing
# ============================================================================

IO.puts("5. Resume/CV Parsing")
IO.puts("   Extract structured resume data with nested work history\n")

defmodule WorkExperienceSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:company, :string)
    field(:title, :string)
    field(:start_date, :string)
    field(:end_date, :string)
    field(:description, :string)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:company, :title, :start_date, :end_date, :description])
    |> validate_required([:company, :title])
  end
end

defmodule EducationSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:institution, :string)
    field(:degree, :string)
    field(:field, :string)
    field(:year, :integer)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:institution, :degree, :field, :year])
    |> validate_required([:institution, :degree])
  end
end

defmodule ResumeSchema do
  use Openrouter.Schema

  embedded_schema do
    field(:name, :string)
    field(:email, :string)
    field(:phone, :string)
    field(:summary, :string)
    embeds_many(:work_experience, WorkExperienceSchema)
    embeds_many(:education, EducationSchema)
    field(:skills, {:array, :string})
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :email, :phone, :summary, :skills])
    |> cast_embed(:work_experience)
    |> cast_embed(:education)
    |> validate_required([:name])
  end
end

text = """
David Chen
Email: david.chen@email.com
Phone: +1-555-999-8888

Summary: Experienced software engineer with 8 years in web development

Work Experience:

Senior Software Engineer at TechStart Inc
March 2020 - Present
Led development of microservices architecture using Elixir and Phoenix

Software Engineer at WebCo
June 2017 - February 2020
Built RESTful APIs and frontend applications

Education:

Bachelor of Science in Computer Science
Stanford University, 2017

Skills: Elixir, Phoenix, PostgreSQL, React, Docker, Kubernetes
"""

{:ok, resume} =
  Openrouter.extract(
    text,
    schema: ResumeSchema,
    model: "openai/gpt-4"
  )

IO.puts("Extracted Resume:")
IO.puts("  Name: #{resume.name}")
IO.puts("  Email: #{resume.email}")
IO.puts("  Phone: #{resume.phone}")
IO.puts("  Summary: #{resume.summary}")
IO.puts("  Work Experience:")

Enum.each(resume.work_experience, fn exp ->
  IO.puts("    #{exp.title} at #{exp.company}")
  IO.puts("    #{exp.start_date} - #{exp.end_date}")
  IO.puts("    #{exp.description}")
  IO.puts("")
end)

IO.puts("  Education:")

Enum.each(resume.education, fn edu ->
  IO.puts("    #{edu.degree} in #{edu.field}")
  IO.puts("    #{edu.institution}, #{edu.year}")
end)

IO.puts("  Skills: #{Enum.join(resume.skills, ", ")}")

IO.puts("")

# ============================================================================
# Example 6: JSON Schema Generation
# ============================================================================

IO.puts("6. JSON Schema Generation")
IO.puts("   View generated JSON schemas for nested structures\n")

json_schema = Openrouter.Schema.to_json_schema(PersonSchema)
IO.puts("PersonSchema JSON Schema:")
IO.inspect(json_schema, pretty: true)

IO.puts("\nCompanySchema JSON Schema:")
company_json_schema = Openrouter.Schema.to_json_schema(CompanySchema)
IO.inspect(company_json_schema, pretty: true)

IO.puts("")

IO.puts("=== Nested Schemas Example Complete ===\n")
