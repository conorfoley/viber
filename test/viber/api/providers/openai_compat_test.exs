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

  test "build_chat_completion_request omits max_tokens when nil (ollama)" do
    request = %MessageRequest{
      model: "llama3",
      max_tokens: nil,
      messages: [InputMessage.user_text("hi")],
      stream: false
    }

    payload = OpenAICompat.build_chat_completion_request(request)
    refute Map.has_key?(payload, :max_tokens)
    refute Map.has_key?(payload, :max_completion_tokens)
  end

  test "build_chat_completion_request omits max_tokens when 0" do
    request = %MessageRequest{
      model: "llama3",
      max_tokens: 0,
      messages: [InputMessage.user_text("hi")],
      stream: false
    }

    payload = OpenAICompat.build_chat_completion_request(request)
    refute Map.has_key?(payload, :max_tokens)
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

  test "stream_events_from_chunks works for ollama model id (prefix stripped)" do
    chunks = [
      %{
        "id" => "chatcmpl-ollama-1",
        "model" => "llama3",
        "choices" => [
          %{"delta" => %{"role" => "assistant", "content" => "Hello"}}
        ]
      },
      %{
        "id" => "chatcmpl-ollama-1",
        "model" => "llama3",
        "choices" => [%{"finish_reason" => "stop"}],
        "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 3}
      }
    ]

    events = OpenAICompat.stream_events_from_chunks("llama3", chunks)

    text_deltas =
      for {:content_block_delta, 0, %{type: "text_delta", text: t}} <- events, do: t

    assert text_deltas == ["Hello"]
  end

  test "ollama config uses localhost default and optional key" do
    config = OpenAICompat.ollama()
    assert config.provider_name == "Ollama"
    assert config.default_base_url == "http://localhost:11434/v1"
    assert config.optional_key == true
  end

  test "normalize_base_url appends /v1 for ollama when missing" do
    config = OpenAICompat.ollama()

    assert OpenAICompat.normalize_base_url("http://localhost:11434", config) ==
             "http://localhost:11434/v1"

    assert OpenAICompat.normalize_base_url("http://localhost:11434/v1", config) ==
             "http://localhost:11434/v1"

    assert OpenAICompat.normalize_base_url("http://localhost:11434/v1/", config) ==
             "http://localhost:11434/v1"
  end

  test "empty api_key_override falls through to env-based validation" do
    config = %OpenAICompat{
      provider_name: "OpenAI",
      api_key_env: "VIBER_TEST_NONEXISTENT_KEY",
      base_url_env: "VIBER_TEST_NONEXISTENT_URL",
      default_base_url: "http://localhost",
      api_key_override: ""
    }

    request = %MessageRequest{
      model: "gpt-4o",
      messages: [InputMessage.user_text("hi")],
      stream: false
    }

    assert {:error, _} = OpenAICompat.send_message(request, config)
  end

  test "nil provider_overrides does not crash" do
    request = %MessageRequest{
      model: "gpt-4o",
      messages: [InputMessage.user_text("hi")],
      stream: false,
      provider_overrides: nil
    }

    payload = OpenAICompat.build_chat_completion_request(request)
    assert payload.model == "gpt-4o"
  end

  test "normalize_finish_reason maps stop reasons" do
    assert OpenAICompat.normalize_finish_reason("stop") == "end_turn"
    assert OpenAICompat.normalize_finish_reason("tool_calls") == "tool_use"
    assert OpenAICompat.normalize_finish_reason("length") == "length"
    assert OpenAICompat.normalize_finish_reason(nil) == nil
  end
end
