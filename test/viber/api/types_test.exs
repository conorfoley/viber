defmodule Viber.API.TypesTest do
  use ExUnit.Case, async: true

  alias Viber.API.{InputMessage, MessageRequest, MessageResponse, Types, ToolDefinition, Usage}

  test "MessageRequest encodes to JSON matching Anthropic API format" do
    req = %MessageRequest{
      model: "claude-sonnet-4-20250514",
      max_tokens: 1024,
      messages: [InputMessage.user_text("Hello")],
      system: "You are helpful.",
      stream: true
    }

    json = Jason.encode!(req) |> Jason.decode!()

    assert json["model"] == "claude-sonnet-4-20250514"
    assert json["max_tokens"] == 1024
    assert json["stream"] == true
    assert json["system"] == "You are helpful."

    assert [%{"role" => "user", "content" => [%{"type" => "text", "text" => "Hello"}]}] =
             json["messages"]

    refute Map.has_key?(json, "tools")
    refute Map.has_key?(json, "tool_choice")
  end

  test "MessageRequest with tool_choice encodes correctly" do
    req = %MessageRequest{
      model: "claude-sonnet-4-20250514",
      max_tokens: 1024,
      messages: [InputMessage.user_text("Hi")],
      tool_choice: {:tool, "read_file"},
      tools: [%ToolDefinition{name: "read_file", input_schema: %{type: "object"}}]
    }

    json = Jason.encode!(req) |> Jason.decode!()
    assert json["tool_choice"] == %{"type" => "tool", "name" => "read_file"}
  end

  test "decode_response/1 parses a MessageResponse JSON" do
    json = %{
      "id" => "msg_123",
      "type" => "message",
      "role" => "assistant",
      "content" => [%{"type" => "text", "text" => "Hello!"}],
      "model" => "claude-sonnet-4-20250514",
      "stop_reason" => "end_turn",
      "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
    }

    resp = Types.decode_response(json)
    assert %MessageResponse{id: "msg_123", role: "assistant"} = resp
    assert [%{type: "text", text: "Hello!"}] = resp.content
    assert resp.stop_reason == "end_turn"
    assert resp.usage.input_tokens == 10
  end

  test "decode_stream_event/1 for each event type" do
    assert {:message_start, %MessageResponse{id: "msg_1"}} =
             Types.decode_stream_event(%{
               "type" => "message_start",
               "message" => %{
                 "id" => "msg_1",
                 "type" => "message",
                 "role" => "assistant",
                 "content" => [],
                 "model" => "claude-sonnet-4-20250514",
                 "usage" => %{"input_tokens" => 0, "output_tokens" => 0}
               }
             })

    assert {:content_block_start, 0, %{type: "text", text: "Hi"}} =
             Types.decode_stream_event(%{
               "type" => "content_block_start",
               "index" => 0,
               "content_block" => %{"type" => "text", "text" => "Hi"}
             })

    assert {:content_block_delta, 0, %{type: "text_delta", text: "Hello"}} =
             Types.decode_stream_event(%{
               "type" => "content_block_delta",
               "index" => 0,
               "delta" => %{"type" => "text_delta", "text" => "Hello"}
             })

    assert {:content_block_stop, 0} =
             Types.decode_stream_event(%{"type" => "content_block_stop", "index" => 0})

    assert {:message_delta, %{"stop_reason" => "end_turn"}, %Usage{}} =
             Types.decode_stream_event(%{
               "type" => "message_delta",
               "delta" => %{"stop_reason" => "end_turn"},
               "usage" => %{"input_tokens" => 10, "output_tokens" => 20}
             })

    assert :message_stop = Types.decode_stream_event(%{"type" => "message_stop"})
  end

  test "InputMessage.user_text/1 constructor" do
    msg = InputMessage.user_text("test")
    assert msg.role == "user"
    assert [%{type: "text", text: "test"}] = msg.content
  end

  test "Usage.total_tokens/1" do
    usage = %Usage{input_tokens: 100, output_tokens: 50}
    assert Usage.total_tokens(usage) == 150
  end
end
