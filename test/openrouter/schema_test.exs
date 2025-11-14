defmodule Openrouter.SchemaTest do
  use ExUnit.Case, async: true

  describe "to_json_schema/1" do
    test "generates JSON schema from simple Ecto schema" do
      defmodule SimpleSchema do
        use Openrouter.Schema

        embedded_schema do
          field :name, :string
          field :age, :integer
          field :active, :boolean
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
          field :tags, {:array, :string}
          field :scores, {:array, :integer}
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
          field :price, :float
          field :created_at, :utc_datetime
          field :metadata, :map
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
        field :name, :string
        field :age, :integer
        field :email, :string
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
        field :name, :string
        field :age, :integer
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
end
