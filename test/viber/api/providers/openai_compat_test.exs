defmodule Viber.API.Providers.OpenAICompatTest do
  use ExUnit.Case, async: true

  alias Viber.API.{InputMessage, MessageRequest, MessageResponse, ToolDefinition, Usage}
  alias Viber.API.Providers.OpenAICompat

  test "build_chat_completion_request translates to OpenAI format" do
    request = %MessageRequest{
      model: "grok-3",
      max_tokens: 64,
      messages: [InputMessage.user_text("hello")],
      system: "be helpful",
      tools: [
        %ToolDefinition{
          name: "weather",
          description: "Get weather",
          input_schema: %{type: "object"}
        }
      ],
      tool_choice: :auto,
      stream: false
    }

    payload = OpenAICompat.build_chat_completion_request(request)

    assert payload.model == "grok-3"
    assert payload.max_tokens == 64
    assert [%{role: "system"} | _] = payload.messages
    assert [%{type: "function"} | _] = payload.tools
    assert payload.tool_choice == "auto"
  end

  test "tool_choice any becomes required" do
    request = %MessageRequest{
      model: "grok-3",
      max_tokens: 64,
      messages: [InputMessage.user_text("hi")],
      tool_choice: :any
    }

    payload = OpenAICompat.build_chat_completion_request(request)
    assert payload.tool_choice == "required"
  end

  test "tool_choice {:tool, name} becomes function object" do
    request = %MessageRequest{
      model: "grok-3",
      max_tokens: 64,
      messages: [InputMessage.user_text("hi")],
      tool_choice: {:tool, "weather"}
    }

    payload = OpenAICompat.build_chat_completion_request(request)
    assert payload.tool_choice == %{type: "function", function: %{name: "weather"}}
  end

  test "normalize_response converts OpenAI format to Anthropic format" do
    openai_response = %{
      "id" => "chatcmpl-123",
      "model" => "grok-3",
      "choices" => [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => "Hello!",
            "tool_calls" => []
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 10,
        "completion_tokens" => 5
      }
    }

    result = OpenAICompat.normalize_response("grok-3", openai_response)

    assert %MessageResponse{} = result
    assert result.id == "chatcmpl-123"
    assert result.type == "message"
    assert result.role == "assistant"
    assert [%{type: "text", text: "Hello!"}] = result.content
    assert result.stop_reason == "end_turn"
    assert result.usage == %Usage{input_tokens: 10, output_tokens: 5}
  end

  test "normalize_response handles tool calls" do
    openai_response = %{
      "id" => "chatcmpl-456",
      "model" => "grok-3",
      "choices" => [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              %{
                "id" => "call_1",
                "function" => %{
                  "name" => "get_weather",
                  "arguments" => "{\"city\":\"Paris\"}"
                }
              }
            ]
          },
          "finish_reason" => "tool_calls"
        }
      ],
      "usage" => %{"prompt_tokens" => 15, "completion_tokens" => 10}
    }

    result = OpenAICompat.normalize_response("grok-3", openai_response)

    assert result.stop_reason == "tool_use"

    assert [%{type: "tool_use", name: "get_weather", input: %{"city" => "Paris"}}] =
             result.content
  end

  test "stream_events_from_chunks emits incremental tool argument deltas" do
    chunks = [
      %{
        "id" => "chatcmpl-stream-1",
        "model" => "grok-3",
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{
                  "index" => 0,
                  "id" => "call_1",
                  "function" => %{"name" => "get_weather", "arguments" => ~s({"city":")}
                }
              ]
            }
          }
        ]
      },
      %{
        "id" => "chatcmpl-stream-1",
        "model" => "grok-3",
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{
                  "index" => 0,
                  "function" => %{"arguments" => ~s(Paris"})}
                }
              ]
            }
          }
        ]
      },
      %{
        "id" => "chatcmpl-stream-1",
        "model" => "grok-3",
        "choices" => [%{"finish_reason" => "tool_calls"}],
        "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
      }
    ]

    events = OpenAICompat.stream_events_from_chunks("grok-3", chunks)

    argument_fragments =
      for {:content_block_delta, 1, %{type: "input_json_delta", partial_json: fragment}} <- events,
          do: fragment

    assert argument_fragments == [~s({"city":"), ~s(Paris"})]
    assert Enum.join(argument_fragments) == ~s({"city":"Paris"})
  end

  test "normalize_finish_reason maps stop reasons" do
    assert OpenAICompat.normalize_finish_reason("stop") == "end_turn"
    assert OpenAICompat.normalize_finish_reason("tool_calls") == "tool_use"
    assert OpenAICompat.normalize_finish_reason("length") == "length"
    assert OpenAICompat.normalize_finish_reason(nil) == nil
  end
end
