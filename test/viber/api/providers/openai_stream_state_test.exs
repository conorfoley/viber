defmodule Viber.API.Providers.OpenAIStreamStateTest do
  use ExUnit.Case, async: true

  alias Viber.API.Providers.OpenAIStreamState
  alias Viber.API.{MessageResponse, Usage}

  describe "new/1" do
    test "initializes with model" do
      state = OpenAIStreamState.new("gpt-4")
      assert state.model == "gpt-4"
      refute state.message_started
      refute state.text_started
    end
  end

  describe "ingest/2 - text streaming" do
    test "first chunk emits message_start and content_block_start" do
      state = OpenAIStreamState.new("gpt-4")

      chunk = %{
        "id" => "chatcmpl-1",
        "model" => "gpt-4",
        "choices" => [%{"delta" => %{"content" => "Hello"}}]
      }

      {events, new_state} = OpenAIStreamState.ingest(state, chunk)

      assert new_state.message_started
      assert new_state.text_started

      assert [
               {:message_start, %MessageResponse{id: "chatcmpl-1", model: "gpt-4"}},
               {:content_block_start, 0, %{type: "text"}},
               {:content_block_delta, 0, %{type: "text_delta", text: "Hello"}}
             ] = events
    end

    test "subsequent chunks emit only text deltas" do
      state = %OpenAIStreamState{
        model: "gpt-4",
        message_started: true,
        text_started: true
      }

      chunk = %{
        "id" => "chatcmpl-1",
        "choices" => [%{"delta" => %{"content" => " world"}}]
      }

      {events, _state} = OpenAIStreamState.ingest(state, chunk)

      assert [{:content_block_delta, 0, %{type: "text_delta", text: " world"}}] = events
    end

    test "empty content is skipped" do
      state = %OpenAIStreamState{model: "gpt-4", message_started: true, text_started: true}

      chunk = %{
        "id" => "chatcmpl-1",
        "choices" => [%{"delta" => %{"content" => ""}}]
      }

      {events, _state} = OpenAIStreamState.ingest(state, chunk)
      assert events == []
    end

    test "nil content is skipped" do
      state = %OpenAIStreamState{model: "gpt-4", message_started: true, text_started: true}

      chunk = %{
        "id" => "chatcmpl-1",
        "choices" => [%{"delta" => %{"content" => nil}}]
      }

      {events, _state} = OpenAIStreamState.ingest(state, chunk)
      assert events == []
    end
  end

  describe "ingest/2 - tool call streaming" do
    test "tool call start emits content_block_start at index+1" do
      state = %OpenAIStreamState{model: "gpt-4", message_started: true}

      chunk = %{
        "id" => "chatcmpl-1",
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{
                  "index" => 0,
                  "id" => "call_abc",
                  "function" => %{"name" => "bash", "arguments" => ~s({"cmd":)}
                }
              ]
            }
          }
        ]
      }

      {events, new_state} = OpenAIStreamState.ingest(state, chunk)

      assert Map.has_key?(new_state.tool_calls, 0)
      assert new_state.tool_calls[0].started

      assert [
               {:content_block_start, 1,
                %{type: "tool_use", id: "call_abc", name: "bash", input: %{}}},
               {:content_block_delta, 1, %{type: "input_json_delta", partial_json: ~s({"cmd":)}}
             ] = events
    end

    test "subsequent argument deltas emit input_json_delta" do
      state = %OpenAIStreamState{
        model: "gpt-4",
        message_started: true,
        tool_calls: %{
          0 => %{
            id: "call_abc",
            name: "bash",
            arguments: ~s({"cmd":),
            started: true,
            stopped: false
          }
        }
      }

      chunk = %{
        "id" => "chatcmpl-1",
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{"index" => 0, "function" => %{"arguments" => ~s("ls"})}}
              ]
            }
          }
        ]
      }

      {events, new_state} = OpenAIStreamState.ingest(state, chunk)

      assert new_state.tool_calls[0].arguments == ~s({"cmd":"ls"})

      assert [
               {:content_block_delta, 1, %{type: "input_json_delta", partial_json: ~s("ls"})}}
             ] = events
    end

    test "multiple parallel tool calls tracked by index" do
      state = %OpenAIStreamState{model: "gpt-4", message_started: true}

      chunk1 = %{
        "id" => "chatcmpl-1",
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{
                  "index" => 0,
                  "id" => "call_1",
                  "function" => %{"name" => "bash", "arguments" => "{}"}
                },
                %{
                  "index" => 1,
                  "id" => "call_2",
                  "function" => %{"name" => "read_file", "arguments" => "{}"}
                }
              ]
            }
          }
        ]
      }

      {events, state} = OpenAIStreamState.ingest(state, chunk1)

      assert Map.has_key?(state.tool_calls, 0)
      assert Map.has_key?(state.tool_calls, 1)

      start_events =
        for {:content_block_start, _, %{type: "tool_use", name: name}} <- events, do: name

      assert "bash" in start_events
      assert "read_file" in start_events
    end
  end

  describe "ingest/2 - usage tracking" do
    test "captures usage from chunk" do
      state = %OpenAIStreamState{model: "gpt-4", message_started: true}

      chunk = %{
        "id" => "chatcmpl-1",
        "choices" => [],
        "usage" => %{"prompt_tokens" => 100, "completion_tokens" => 50}
      }

      {_events, new_state} = OpenAIStreamState.ingest(state, chunk)
      assert new_state.usage == %Usage{input_tokens: 100, output_tokens: 50}
    end
  end

  describe "ingest/2 - finish_reason" do
    test "captures stop reason" do
      state = %OpenAIStreamState{model: "gpt-4", message_started: true}

      chunk = %{
        "id" => "chatcmpl-1",
        "choices" => [%{"finish_reason" => "stop"}]
      }

      {_events, new_state} = OpenAIStreamState.ingest(state, chunk)
      assert new_state.stop_reason == "end_turn"
    end

    test "captures tool_calls finish reason" do
      state = %OpenAIStreamState{model: "gpt-4", message_started: true}

      chunk = %{
        "id" => "chatcmpl-1",
        "choices" => [%{"finish_reason" => "tool_calls"}]
      }

      {_events, new_state} = OpenAIStreamState.ingest(state, chunk)
      assert new_state.stop_reason == "tool_use"
    end
  end

  describe "finish/1" do
    test "emits content_block_stop for text" do
      state = %OpenAIStreamState{
        model: "gpt-4",
        message_started: true,
        text_started: true,
        stop_reason: "end_turn"
      }

      events = OpenAIStreamState.finish(state)

      assert {:content_block_stop, 0} in events
      assert {:message_delta, %{"stop_reason" => "end_turn"}, _usage} = Enum.at(events, -2)
      assert :message_stop == List.last(events)
    end

    test "emits content_block_stop for tool calls" do
      state = %OpenAIStreamState{
        model: "gpt-4",
        message_started: true,
        stop_reason: "tool_use",
        tool_calls: %{
          0 => %{id: "call_1", name: "bash", arguments: "{}", started: true, stopped: false}
        }
      }

      events = OpenAIStreamState.finish(state)

      assert {:content_block_stop, 1} in events
      assert :message_stop == List.last(events)
    end

    test "emits start+stop for unstarted tool call with name" do
      state = %OpenAIStreamState{
        model: "gpt-4",
        message_started: true,
        tool_calls: %{
          0 => %{id: "call_1", name: "bash", arguments: "{}", started: false, stopped: false}
        }
      }

      events = OpenAIStreamState.finish(state)

      start_events =
        for {:content_block_start, _, %{type: "tool_use"}} = e <- events, do: e

      assert length(start_events) == 1
      assert {:content_block_stop, 1} in events
    end

    test "returns empty for unstarted message" do
      state = OpenAIStreamState.new("gpt-4")
      assert OpenAIStreamState.finish(state) == []
    end

    test "returns empty for already finished state" do
      state = %OpenAIStreamState{model: "gpt-4", message_started: true, finished: true}
      assert OpenAIStreamState.finish(state) == []
    end

    test "defaults stop_reason to end_turn" do
      state = %OpenAIStreamState{model: "gpt-4", message_started: true}
      events = OpenAIStreamState.finish(state)

      assert {:message_delta, %{"stop_reason" => "end_turn"}, _usage} = Enum.at(events, -2)
    end
  end

  describe "events_from_chunks/2 - full integration" do
    test "text-only conversation" do
      chunks = [
        %{
          "id" => "chatcmpl-1",
          "model" => "gpt-4",
          "choices" => [%{"delta" => %{"content" => "Hello"}}]
        },
        %{
          "id" => "chatcmpl-1",
          "choices" => [%{"delta" => %{"content" => " world"}}]
        },
        %{
          "id" => "chatcmpl-1",
          "choices" => [%{"finish_reason" => "stop"}],
          "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 2}
        }
      ]

      events = OpenAIStreamState.events_from_chunks("gpt-4", chunks)

      text_deltas =
        for {:content_block_delta, 0, %{type: "text_delta", text: t}} <- events, do: t

      assert Enum.join(text_deltas) == "Hello world"

      assert {:message_start, %MessageResponse{}} = hd(events)
      assert :message_stop == List.last(events)
    end

    test "tool call with fragmented arguments" do
      chunks = [
        %{
          "id" => "chatcmpl-1",
          "model" => "gpt-4",
          "choices" => [
            %{
              "delta" => %{
                "tool_calls" => [
                  %{
                    "index" => 0,
                    "id" => "call_1",
                    "function" => %{"name" => "bash", "arguments" => ~s({"command":")}
                  }
                ]
              }
            }
          ]
        },
        %{
          "id" => "chatcmpl-1",
          "choices" => [
            %{
              "delta" => %{
                "tool_calls" => [
                  %{"index" => 0, "function" => %{"arguments" => ~s(ls -la"})}}
                ]
              }
            }
          ]
        },
        %{
          "id" => "chatcmpl-1",
          "choices" => [%{"finish_reason" => "tool_calls"}],
          "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 10}
        }
      ]

      events = OpenAIStreamState.events_from_chunks("gpt-4", chunks)

      argument_fragments =
        for {:content_block_delta, 1, %{type: "input_json_delta", partial_json: f}} <- events,
            do: f

      assert Enum.join(argument_fragments) == ~s({"command":"ls -la"})
    end

    test "text followed by tool call" do
      chunks = [
        %{
          "id" => "chatcmpl-1",
          "model" => "gpt-4",
          "choices" => [%{"delta" => %{"content" => "Let me check."}}]
        },
        %{
          "id" => "chatcmpl-1",
          "choices" => [
            %{
              "delta" => %{
                "tool_calls" => [
                  %{
                    "index" => 0,
                    "id" => "call_1",
                    "function" => %{"name" => "bash", "arguments" => ~s({"command":"ls"})}
                  }
                ]
              }
            }
          ]
        },
        %{
          "id" => "chatcmpl-1",
          "choices" => [%{"finish_reason" => "tool_calls"}],
          "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 10}
        }
      ]

      events = OpenAIStreamState.events_from_chunks("gpt-4", chunks)

      text_deltas =
        for {:content_block_delta, 0, %{type: "text_delta", text: t}} <- events, do: t

      tool_starts =
        for {:content_block_start, _, %{type: "tool_use", name: n}} <- events, do: n

      assert Enum.join(text_deltas) == "Let me check."
      assert tool_starts == ["bash"]
    end
  end
end
