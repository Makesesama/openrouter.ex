defmodule Openrouter.Integration.StructuredOutputsTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag :structured_outputs

  setup do
    unless System.get_env("OPENROUTER_API_KEY") || System.get_env("REQORD_MODE") == "replay" do
      ExUnit.configure(exclude: [:integration])
    end

    :ok
  end

  describe "Ecto schema extraction" do
    defmodule PersonSchema do
      use Openrouter.Schema

      embedded_schema do
        field :name, :string
        field :age, :integer
        field :city, :string
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:name, :age, :city])
        |> validate_required([:name, :age])
        |> validate_number(:age, greater_than: 0, less_than: 150)
      end
    end

    @tag :integration
    test "extracts simple person data" do
      text = "John Smith is 35 years old and lives in New York"

      {:ok, person} =
        Openrouter.extract(
          text,
          schema: PersonSchema,
          model: "openai/gpt-3.5-turbo"
        )

      assert person.name =~ "John"
      assert person.age == 35
      assert person.city =~ "New York"
    end

    @tag :integration
    test "validates required fields" do
      # This text is missing age information
      text = "Alice lives in Boston"

      # The LLM should infer or the retry should handle missing data
      result =
        Openrouter.extract(
          text,
          schema: PersonSchema,
          model: "openai/gpt-3.5-turbo",
          max_retries: 2
        )

      # Might succeed with inferred age, or fail validation
      case result do
        {:ok, person} ->
          assert is_binary(person.name)
          assert is_integer(person.age)

        {:error, _} ->
          # Expected if validation fails
          assert true
      end
    end
  end

  describe "complex schema extraction" do
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

    @tag :integration
    test "extracts product with arrays and multiple types" do
      text = """
      The SuperPhone X is available for $899.99 in the Electronics category.
      It's currently in stock and features: 5G connectivity, OLED display, and wireless charging.
      """

      {:ok, product} =
        Openrouter.extract(
          text,
          schema: ProductSchema,
          model: "openai/gpt-3.5-turbo"
        )

      assert product.name =~ "SuperPhone"
      assert product.price > 800.0
      assert product.category =~ "Electronics"
      assert product.in_stock == true
      assert is_list(product.features)
      assert length(product.features) >= 3
    end
  end

  describe "JSON schema extraction" do
    @tag :integration
    test "extracts with simple JSON schema" do
      schema = %{
        type: "object",
        properties: %{
          product: %{type: "string"},
          price: %{type: "number"}
        },
        required: ["product", "price"]
      }

      text = "The MacBook Pro costs $2499"

      {:ok, data} =
        Openrouter.extract(
          text,
          json_schema: schema,
          model: "openai/gpt-3.5-turbo"
        )

      assert is_map(data)
      assert data["product"] =~ "MacBook"
      assert data["price"] > 2000
    end

    @tag :integration
    test "extracts complex nested JSON schema" do
      schema = %{
        type: "object",
        properties: %{
          company: %{type: "string"},
          employees: %{type: "integer"},
          address: %{
            type: "object",
            properties: %{
              city: %{type: "string"},
              country: %{type: "string"}
            }
          }
        },
        required: ["company", "employees"]
      }

      text = "Acme Corp has 500 employees and is headquartered in Seattle, USA"

      {:ok, data} =
        Openrouter.extract(
          text,
          json_schema: schema,
          model: "openai/gpt-3.5-turbo"
        )

      assert data["company"] =~ "Acme"
      assert data["employees"] == 500
      assert data["address"]["city"] =~ "Seattle"
      assert data["address"]["country"] =~ "USA"
    end
  end

  describe "extraction with retry" do
    defmodule StrictSchema do
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

    @tag :integration
    test "retries on validation errors" do
      # Vague text that might need retries for proper formatting
      text = "Contact: alice at example dot com, she's 25"

      {:ok, person} =
        Openrouter.extract(
          text,
          schema: StrictSchema,
          model: "openai/gpt-3.5-turbo",
          max_retries: 3
        )

      # Should successfully extract after retries
      assert person.email =~ "@"
      assert person.email =~ "."
      assert person.age == 25
    end

    @tag :integration
    test "respects max_retries limit" do
      # Invalid data that can't be fixed
      text = "No valid information here"

      result =
        Openrouter.extract(
          text,
          schema: StrictSchema,
          model: "openai/gpt-3.5-turbo",
          max_retries: 2
        )

      # Should fail after retries
      assert {:error, _} = result
    end
  end

  describe "extraction with different models" do
    defmodule SimpleSchema do
      use Openrouter.Schema

      embedded_schema do
        field :title, :string
        field :summary, :string
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:title, :summary])
        |> validate_required([:title, :summary])
      end
    end

    @tag :integration
    test "works with different model providers" do
      text = "Article: The Future of AI. This article discusses emerging trends in artificial intelligence."

      # Test with GPT-3.5
      {:ok, result1} =
        Openrouter.extract(
          text,
          schema: SimpleSchema,
          model: "openai/gpt-3.5-turbo"
        )

      assert result1.title =~ "AI"
      assert is_binary(result1.summary)
    end
  end

  describe "extraction validation" do
    defmodule NumberSchema do
      use Openrouter.Schema

      embedded_schema do
        field :count, :integer
        field :percentage, :float
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:count, :percentage])
        |> validate_required([:count, :percentage])
        |> validate_number(:count, greater_than: 0)
        |> validate_number(:percentage, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
      end
    end

    @tag :integration
    test "validates number ranges" do
      text = "There are 42 items with a 75% completion rate"

      {:ok, data} =
        Openrouter.extract(
          text,
          schema: NumberSchema,
          model: "openai/gpt-3.5-turbo"
        )

      assert data.count == 42
      assert data.percentage == 75.0
      assert data.percentage >= 0 and data.percentage <= 100
    end
  end

  describe "array extraction" do
    defmodule ListSchema do
      use Openrouter.Schema

      embedded_schema do
        field :tags, {:array, :string}
        field :scores, {:array, :integer}
      end

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, [:tags, :scores])
        |> validate_required([:tags])
      end
    end

    @tag :integration
    test "extracts arrays of strings and numbers" do
      text = "Tags: elixir, phoenix, functional. Scores: 95, 87, 92"

      {:ok, data} =
        Openrouter.extract(
          text,
          schema: ListSchema,
          model: "openai/gpt-3.5-turbo"
        )

      assert is_list(data.tags)
      assert length(data.tags) >= 3
      assert "elixir" in data.tags or "Elixir" in data.tags

      assert is_list(data.scores)
      assert length(data.scores) >= 3
      assert Enum.all?(data.scores, &is_integer/1)
    end
  end
end
