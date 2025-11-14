defmodule Openrouter.Types.ToolCallTest do
  use ExUnit.Case, async: true

  alias Openrouter.Types.{ToolCall, Response}

  describe "ToolCall.from_api_format/1" do
    test "creates tool call from API format with string keys" do
      data = %{
        "id" => "call_123",
        "type" => "function",
        "function" => %{
          "name" => "get_weather",
          "arguments" => ~s({"location": "Paris"})
        }
      }

      tool_call = ToolCall.from_api_format(data)

      assert tool_call.id == "call_123"
      assert tool_call.type == "function"
      assert tool_call.function.name == "get_weather"
      assert tool_call.function.arguments == ~s({"location": "Paris"})
    end

    test "creates tool call from API format with atom keys" do
      data = %{
        id: "call_456",
        type: "function",
        function: %{
          name: "calculator",
          arguments: ~s({"a": 5, "b": 3})
        }
      }

      tool_call = ToolCall.from_api_format(data)

      assert tool_call.id == "call_456"
      assert tool_call.type == "function"
      assert tool_call.function.name == "calculator"
      assert tool_call.function.arguments == ~s({"a": 5, "b": 3})
    end

    test "defaults type to 'function' if not provided" do
      data = %{
        "id" => "call_789",
        "function" => %{
          "name" => "test",
          "arguments" => "{}"
        }
      }

      tool_call = ToolCall.from_api_format(data)

      assert tool_call.type == "function"
    end

    test "handles mixed string and atom keys" do
      data = %{
        "id" => "call_mix",
        type: "function",
        "function" => %{
          name: "mixed_tool",
          "arguments" => "{}"
        }
      }

      tool_call = ToolCall.from_api_format(data)

      assert tool_call.id == "call_mix"
      assert tool_call.type == "function"
      assert tool_call.function.name == "mixed_tool"
    end
  end

  describe "ToolCall.to_api_format/1" do
    test "converts tool call to API format" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "get_weather",
          arguments: ~s({"location": "Paris"})
        }
      }

      api_format = ToolCall.to_api_format(tool_call)

      assert api_format.id == "call_123"
      assert api_format.type == "function"
      assert api_format.function.name == "get_weather"
      assert api_format.function.arguments == ~s({"location": "Paris"})
    end

    test "roundtrip conversion preserves data" do
      original = %{
        "id" => "call_test",
        "type" => "function",
        "function" => %{
          "name" => "test_tool",
          "arguments" => ~s({"key": "value"})
        }
      }

      tool_call = ToolCall.from_api_format(original)
      converted = ToolCall.to_api_format(tool_call)

      assert converted.id == original["id"]
      assert converted.type == original["type"]
      assert converted.function.name == original["function"]["name"]
      assert converted.function.arguments == original["function"]["arguments"]
    end
  end

  describe "ToolCall.parse_arguments/1" do
    test "parses simple JSON arguments" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "get_weather",
          arguments: ~s({"location": "Paris"})
        }
      }

      assert {:ok, %{"location" => "Paris"}} = ToolCall.parse_arguments(tool_call)
    end

    test "parses complex JSON arguments" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "process_data",
          arguments: ~s({"items": [1, 2, 3], "options": {"format": "json", "validate": true}})
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments(tool_call)
      assert args["items"] == [1, 2, 3]
      assert args["options"]["format"] == "json"
      assert args["options"]["validate"] == true
    end

    test "parses empty JSON object" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "no_args",
          arguments: "{}"
        }
      }

      assert {:ok, %{}} = ToolCall.parse_arguments(tool_call)
    end

    test "handles invalid JSON" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "bad_args",
          arguments: "not valid json"
        }
      }

      assert {:error, %Jason.DecodeError{}} = ToolCall.parse_arguments(tool_call)
    end

    test "parses arguments with special characters" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "send_message",
          arguments: ~s({"message": "Hello \\"world\\"!", "emoji": "👋"})
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments(tool_call)
      assert args["message"] == ~s(Hello "world"!)
      assert args["emoji"] == "👋"
    end

    test "parses arguments with numbers" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "calculator",
          arguments: ~s({"a": 42, "b": 3.14, "c": -100})
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments(tool_call)
      assert args["a"] == 42
      assert args["b"] == 3.14
      assert args["c"] == -100
    end

    test "parses arguments with booleans and null" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "config",
          arguments: ~s({"enabled": true, "disabled": false, "value": null})
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments(tool_call)
      assert args["enabled"] == true
      assert args["disabled"] == false
      assert args["value"] == nil
    end
  end

  describe "ToolCall.parse_arguments_atomized/1" do
    test "parses and atomizes simple arguments" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "get_weather",
          arguments: ~s({"location": "Paris", "unit": "celsius"})
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments_atomized(tool_call)
      assert args == %{location: "Paris", unit: "celsius"}
    end

    test "atomizes all top-level keys" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "create_user",
          arguments: ~s({"name": "Alice", "age": 30, "email": "alice@example.com"})
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments_atomized(tool_call)
      assert args.name == "Alice"
      assert args.age == 30
      assert args.email == "alice@example.com"
    end

    test "handles nested objects (only top-level atomized)" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "process",
          arguments: ~s({"data": {"nested": "value"}})
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments_atomized(tool_call)
      assert args.data == %{"nested" => "value"}
    end

    test "handles empty arguments" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "no_args",
          arguments: "{}"
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments_atomized(tool_call)
      assert args == %{}
    end

    test "returns error for invalid JSON" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "bad",
          arguments: "invalid"
        }
      }

      assert {:error, %Jason.DecodeError{}} = ToolCall.parse_arguments_atomized(tool_call)
    end
  end

  describe "ToolCall.create_result_message/2" do
    test "creates result message with string content" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "get_weather",
          arguments: ~s({"location": "Paris"})
        }
      }

      message = ToolCall.create_result_message(tool_call, "Sunny, 72°F")

      assert message.role == "tool"
      assert message.tool_call_id == "call_123"
      assert message.content == "Sunny, 72°F"
    end

    test "creates result message with map content" do
      tool_call = %ToolCall{
        id: "call_456",
        type: "function",
        function: %{
          name: "get_user",
          arguments: ~s({"id": 123})
        }
      }

      result = %{name: "Alice", email: "alice@example.com"}
      message = ToolCall.create_result_message(tool_call, result)

      assert message.role == "tool"
      assert message.tool_call_id == "call_456"

      # Content should be JSON encoded
      assert {:ok, decoded} = Jason.decode(message.content)
      assert decoded["name"] == "Alice"
      assert decoded["email"] == "alice@example.com"
    end

    test "creates result message with list content" do
      tool_call = %ToolCall{
        id: "call_789",
        type: "function",
        function: %{
          name: "list_items",
          arguments: "{}"
        }
      }

      result = ["item1", "item2", "item3"]
      message = ToolCall.create_result_message(tool_call, result)

      assert message.role == "tool"
      assert {:ok, decoded} = Jason.decode(message.content)
      assert decoded == ["item1", "item2", "item3"]
    end

    test "creates result message with number content" do
      tool_call = %ToolCall{
        id: "call_num",
        type: "function",
        function: %{
          name: "calculate",
          arguments: ~s({"a": 5, "b": 3})
        }
      }

      message = ToolCall.create_result_message(tool_call, 42)

      assert message.role == "tool"
      assert message.content == "42"
    end

    test "creates result message with boolean content" do
      tool_call = %ToolCall{
        id: "call_bool",
        type: "function",
        function: %{
          name: "check",
          arguments: "{}"
        }
      }

      message = ToolCall.create_result_message(tool_call, true)

      assert message.role == "tool"
      assert message.content == "true"
    end
  end

  describe "ToolCall.has_function?/2" do
    test "returns true when function name matches (string)" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "get_weather",
          arguments: "{}"
        }
      }

      assert ToolCall.has_function?(tool_call, "get_weather")
    end

    test "returns true when function name matches (atom)" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "get_weather",
          arguments: "{}"
        }
      }

      assert ToolCall.has_function?(tool_call, :get_weather)
    end

    test "returns false when function name doesn't match" do
      tool_call = %ToolCall{
        id: "call_123",
        type: "function",
        function: %{
          name: "get_weather",
          arguments: "{}"
        }
      }

      refute ToolCall.has_function?(tool_call, "calculator")
      refute ToolCall.has_function?(tool_call, :calculator)
    end
  end

  describe "ToolCall.from_response/1" do
    test "extracts tool calls from response" do
      response = %Response{
        content: "",
        role: :assistant,
        tool_calls: [
          %{
            "id" => "call_1",
            "type" => "function",
            "function" => %{
              "name" => "get_weather",
              "arguments" => ~s({"location": "Paris"})
            }
          },
          %{
            "id" => "call_2",
            "type" => "function",
            "function" => %{
              "name" => "calculator",
              "arguments" => ~s({"a": 5, "b": 3})
            }
          }
        ]
      }

      tool_calls = ToolCall.from_response(response)

      assert length(tool_calls) == 2
      assert Enum.at(tool_calls, 0).id == "call_1"
      assert Enum.at(tool_calls, 0).function.name == "get_weather"
      assert Enum.at(tool_calls, 1).id == "call_2"
      assert Enum.at(tool_calls, 1).function.name == "calculator"
    end

    test "returns empty list when no tool calls" do
      response = %Response{
        content: "Hello",
        role: :assistant,
        tool_calls: nil
      }

      assert ToolCall.from_response(response) == []
    end

    test "handles empty tool calls array" do
      response = %Response{
        content: "Hello",
        role: :assistant,
        tool_calls: []
      }

      assert ToolCall.from_response(response) == []
    end
  end

  describe "ToolCall.has_tool_calls?/1" do
    test "returns true when response has tool calls" do
      response = %Response{
        content: "",
        role: :assistant,
        tool_calls: [
          %{
            "id" => "call_1",
            "type" => "function",
            "function" => %{
              "name" => "test",
              "arguments" => "{}"
            }
          }
        ]
      }

      assert ToolCall.has_tool_calls?(response)
    end

    test "returns false when tool_calls is nil" do
      response = %Response{
        content: "Hello",
        role: :assistant,
        tool_calls: nil
      }

      refute ToolCall.has_tool_calls?(response)
    end

    test "returns false when tool_calls is empty array" do
      response = %Response{
        content: "Hello",
        role: :assistant,
        tool_calls: []
      }

      refute ToolCall.has_tool_calls?(response)
    end
  end

  describe "ToolCall edge cases" do
    test "handles tool call with complex nested arguments" do
      tool_call = %ToolCall{
        id: "call_complex",
        type: "function",
        function: %{
          name: "complex_tool",
          arguments: ~s({
            "user": {
              "name": "Alice",
              "settings": {
                "theme": "dark",
                "notifications": {
                  "email": true,
                  "sms": false
                }
              }
            },
            "tags": ["important", "urgent"]
          })
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments(tool_call)
      assert args["user"]["name"] == "Alice"
      assert args["user"]["settings"]["theme"] == "dark"
      assert args["user"]["settings"]["notifications"]["email"] == true
      assert args["tags"] == ["important", "urgent"]
    end

    test "handles tool call with unicode characters" do
      tool_call = %ToolCall{
        id: "call_unicode",
        type: "function",
        function: %{
          name: "translate",
          arguments: ~s({"text": "Hello 世界 🌍", "to": "ja"})
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments(tool_call)
      assert args["text"] == "Hello 世界 🌍"
    end

    test "handles tool call with very long arguments" do
      long_text = String.duplicate("a", 10_000)

      tool_call = %ToolCall{
        id: "call_long",
        type: "function",
        function: %{
          name: "process_text",
          arguments: Jason.encode!(%{text: long_text})
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments(tool_call)
      assert String.length(args["text"]) == 10_000
    end

    test "handles tool call with escaped quotes in arguments" do
      tool_call = %ToolCall{
        id: "call_quotes",
        type: "function",
        function: %{
          name: "echo",
          arguments: ~s({"message": "She said \\"hello\\" to me"})
        }
      }

      assert {:ok, args} = ToolCall.parse_arguments(tool_call)
      assert args["message"] == ~s(She said "hello" to me)
    end
  end
end
