defmodule Openrouter.SchemaTest do
  use ExUnit.Case, async: true

  describe "to_json_schema/1" do
    test "generates JSON schema from simple Ecto schema" do
      defmodule SimpleSchema do
        use Openrouter.Schema

        embedded_schema do
          field(:name, :string)
          field(:age, :integer)
          field(:active, :boolean)
        end
      end

      schema = Openrouter.Schema.to_json_schema(SimpleSchema)

      assert schema[:type] == "object"
      assert schema[:properties][:name] == %{type: "string"}
      assert schema[:properties][:age] == %{type: "integer"}
      assert schema[:properties][:active] == %{type: "boolean"}
    end

    test "generates JSON schema with arrays" do
      defmodule ArraySchema do
        use Openrouter.Schema

        embedded_schema do
          field(:tags, {:array, :string})
          field(:scores, {:array, :integer})
        end
      end

      schema = Openrouter.Schema.to_json_schema(ArraySchema)

      assert schema[:properties][:tags] == %{type: "array", items: %{type: "string"}}
      assert schema[:properties][:scores] == %{type: "array", items: %{type: "integer"}}
    end

    test "generates JSON schema with various types" do
      defmodule TypesSchema do
        use Openrouter.Schema

        embedded_schema do
          field(:price, :float)
          field(:created_at, :utc_datetime)
          field(:metadata, :map)
        end
      end

      schema = Openrouter.Schema.to_json_schema(TypesSchema)

      assert schema[:properties][:price] == %{type: "number"}
      assert schema[:properties][:created_at] == %{type: "string", format: "date-time"}
      assert schema[:properties][:metadata] == %{type: "object"}
    end
  end

  describe "validate/2" do
    defmodule UserSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:name, :string)
        field(:age, :integer)
        field(:email, :string)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:name, :age, :email])
        |> validate_required([:name, :age])
        |> validate_number(:age, greater_than: 0, less_than: 150)
        |> validate_format(:email, ~r/@/)
      end
    end

    test "validates valid data" do
      data = %{
        "name" => "John Doe",
        "age" => 30,
        "email" => "john@example.com"
      }

      assert {:ok, user} = Openrouter.Schema.validate(UserSchema, data)
      assert user.name == "John Doe"
      assert user.age == 30
      assert user.email == "john@example.com"
    end

    test "fails validation for missing required fields" do
      data = %{"name" => "John"}

      assert {:error, changeset} = Openrouter.Schema.validate(UserSchema, data)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :age)
    end

    test "fails validation for invalid email format" do
      data = %{
        "name" => "John",
        "age" => 30,
        "email" => "invalid-email"
      }

      assert {:error, changeset} = Openrouter.Schema.validate(UserSchema, data)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :email)
    end

    test "fails validation for age out of range" do
      data = %{
        "name" => "John",
        "age" => 200,
        "email" => "john@example.com"
      }

      assert {:error, changeset} = Openrouter.Schema.validate(UserSchema, data)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :age)
    end
  end

  describe "format_errors/1" do
    defmodule ValidationSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:name, :string)
        field(:age, :integer)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:name, :age])
        |> validate_required([:name, :age])
      end
    end

    test "formats validation errors as readable string" do
      data = %{}
      {:error, changeset} = Openrouter.Schema.validate(ValidationSchema, data)

      error_string = Openrouter.Schema.format_errors(changeset)

      assert error_string =~ "name"
      assert error_string =~ "age"
      assert is_binary(error_string)
    end
  end

  describe "nested schemas - embeds_one" do
    defmodule AddressSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:street, :string)
        field(:city, :string)
        field(:zip_code, :string)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:street, :city, :zip_code])
        |> validate_required([:city])
      end
    end

    defmodule PersonSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:name, :string)
        field(:age, :integer)
        embeds_one(:address, AddressSchema)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:name, :age])
        |> cast_embed(:address)
        |> validate_required([:name])
      end
    end

    test "generates JSON schema with embeds_one" do
      schema = Openrouter.Schema.to_json_schema(PersonSchema)

      assert schema[:type] == "object"
      assert schema[:properties][:name] == %{type: "string"}
      assert schema[:properties][:age] == %{type: "integer"}

      # Nested address schema
      address_schema = schema[:properties][:address]
      assert address_schema[:type] == "object"
      assert address_schema[:properties][:street] == %{type: "string"}
      assert address_schema[:properties][:city] == %{type: "string"}
      assert address_schema[:properties][:zip_code] == %{type: "string"}
    end

    test "validates data with embeds_one" do
      data = %{
        "name" => "Alice",
        "age" => 25,
        "address" => %{
          "street" => "123 Main St",
          "city" => "New York",
          "zip_code" => "10001"
        }
      }

      assert {:ok, person} = Openrouter.Schema.validate(PersonSchema, data)
      assert person.name == "Alice"
      assert person.address.city == "New York"
      assert person.address.street == "123 Main St"
    end

    test "validates nested required fields in embeds_one" do
      data = %{
        "name" => "Bob",
        "address" => %{
          "street" => "456 Oak Ave"
          # Missing required city
        }
      }

      assert {:error, changeset} = Openrouter.Schema.validate(PersonSchema, data)
      refute changeset.valid?
    end
  end

  describe "nested schemas - embeds_many" do
    defmodule PhoneSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:type, :string)
        field(:number, :string)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:type, :number])
        |> validate_required([:type, :number])
      end
    end

    defmodule ContactSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:name, :string)
        embeds_many(:phones, PhoneSchema)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:name])
        |> cast_embed(:phones)
        |> validate_required([:name])
      end
    end

    test "generates JSON schema with embeds_many" do
      schema = Openrouter.Schema.to_json_schema(ContactSchema)

      assert schema[:type] == "object"
      assert schema[:properties][:name] == %{type: "string"}

      # Array of phone schemas
      phones_schema = schema[:properties][:phones]
      assert phones_schema[:type] == "array"
      assert phones_schema[:items][:type] == "object"
      assert phones_schema[:items][:properties][:type] == %{type: "string"}
      assert phones_schema[:items][:properties][:number] == %{type: "string"}
    end

    test "validates data with embeds_many" do
      data = %{
        "name" => "Carol",
        "phones" => [
          %{"type" => "mobile", "number" => "+1-555-1234"},
          %{"type" => "home", "number" => "+1-555-5678"}
        ]
      }

      assert {:ok, contact} = Openrouter.Schema.validate(ContactSchema, data)
      assert contact.name == "Carol"
      assert length(contact.phones) == 2
      assert Enum.at(contact.phones, 0).type == "mobile"
      assert Enum.at(contact.phones, 1).number == "+1-555-5678"
    end

    test "validates nested required fields in embeds_many" do
      data = %{
        "name" => "Dave",
        "phones" => [
          %{"type" => "mobile", "number" => "+1-555-1111"},
          %{"type" => "work"}
          # Missing required number in second phone
        ]
      }

      assert {:error, changeset} = Openrouter.Schema.validate(ContactSchema, data)
      refute changeset.valid?
    end
  end

  describe "deeply nested schemas" do
    defmodule EmployeeSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:name, :string)
        field(:title, :string)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:name, :title])
        |> validate_required([:name])
      end
    end

    defmodule DepartmentSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:name, :string)
        embeds_many(:employees, EmployeeSchema)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:name])
        |> cast_embed(:employees)
        |> validate_required([:name])
      end
    end

    defmodule CompanySchema do
      use Openrouter.Schema

      embedded_schema do
        field(:name, :string)
        embeds_many(:departments, DepartmentSchema)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:name])
        |> cast_embed(:departments)
        |> validate_required([:name])
      end
    end

    test "generates JSON schema with deep nesting" do
      schema = Openrouter.Schema.to_json_schema(CompanySchema)

      assert schema[:type] == "object"
      assert schema[:properties][:name] == %{type: "string"}

      # Departments array
      dept_schema = schema[:properties][:departments]
      assert dept_schema[:type] == "array"
      assert dept_schema[:items][:type] == "object"
      assert dept_schema[:items][:properties][:name] == %{type: "string"}

      # Employees array within departments
      emp_schema = dept_schema[:items][:properties][:employees]
      assert emp_schema[:type] == "array"
      assert emp_schema[:items][:type] == "object"
      assert emp_schema[:items][:properties][:name] == %{type: "string"}
      assert emp_schema[:items][:properties][:title] == %{type: "string"}
    end

    test "validates deeply nested data" do
      data = %{
        "name" => "TechCorp",
        "departments" => [
          %{
            "name" => "Engineering",
            "employees" => [
              %{"name" => "Alice", "title" => "Senior Engineer"},
              %{"name" => "Bob", "title" => "Junior Engineer"}
            ]
          },
          %{
            "name" => "Marketing",
            "employees" => [
              %{"name" => "Carol", "title" => "Marketing Manager"}
            ]
          }
        ]
      }

      assert {:ok, company} = Openrouter.Schema.validate(CompanySchema, data)
      assert company.name == "TechCorp"
      assert length(company.departments) == 2
      assert length(Enum.at(company.departments, 0).employees) == 2
      assert Enum.at(Enum.at(company.departments, 0).employees, 0).name == "Alice"
    end
  end

  describe "mixed nested types" do
    defmodule ProductSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:name, :string)
        field(:price, :float)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:name, :price])
        |> validate_required([:name, :price])
      end
    end

    defmodule ShippingSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:address, :string)
        field(:method, :string)
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:address, :method])
        |> validate_required([:address])
      end
    end

    defmodule OrderSchema do
      use Openrouter.Schema

      embedded_schema do
        field(:order_id, :string)
        embeds_many(:products, ProductSchema)
        embeds_one(:shipping, ShippingSchema)
        field(:tags, {:array, :string})
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:order_id, :tags])
        |> cast_embed(:products)
        |> cast_embed(:shipping)
        |> validate_required([:order_id])
      end
    end

    test "generates schema with mixed nested types" do
      schema = Openrouter.Schema.to_json_schema(OrderSchema)

      assert schema[:properties][:order_id] == %{type: "string"}

      # embeds_many
      assert schema[:properties][:products][:type] == "array"
      assert schema[:properties][:products][:items][:type] == "object"

      # embeds_one
      assert schema[:properties][:shipping][:type] == "object"

      # regular array
      assert schema[:properties][:tags][:type] == "array"
      assert schema[:properties][:tags][:items] == %{type: "string"}
    end

    test "validates mixed nested data" do
      data = %{
        "order_id" => "ORD-123",
        "products" => [
          %{"name" => "Widget", "price" => 9.99},
          %{"name" => "Gadget", "price" => 19.99}
        ],
        "shipping" => %{
          "address" => "123 Main St",
          "method" => "Express"
        },
        "tags" => ["urgent", "gift"]
      }

      assert {:ok, order} = Openrouter.Schema.validate(OrderSchema, data)
      assert order.order_id == "ORD-123"
      assert length(order.products) == 2
      assert order.shipping.method == "Express"
      assert order.tags == ["urgent", "gift"]
    end
  end
end
