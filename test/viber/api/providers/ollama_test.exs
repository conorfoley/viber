defmodule Viber.API.Providers.OllamaTest do
  use ExUnit.Case, async: true

  alias Viber.API.Providers.Ollama

  test "lists installed models from Ollama tags endpoint" do
    test_pid = self()

    request_fun = fn url, opts ->
      send(test_pid, {:request, url, opts})

      {:ok,
       %{
         status: 200,
         body: %{
           "models" => [
             %{"name" => "qwen3.8:latest"},
             %{"name" => "llama3:8b"}
           ]
         }
       }}
    end

    assert {:ok, ["qwen3.8:latest", "llama3:8b"]} =
             Ollama.list_models(
               base_url: "http://localhost:11434/v1",
               request_fun: request_fun
             )

    assert_receive {:request, "http://localhost:11434/api/tags", receive_timeout: 1_500}
  end

  test "returns an error when Ollama cannot be reached" do
    request_fun = fn _url, _opts -> {:error, :econnrefused} end

    assert {:error, :econnrefused} = Ollama.list_models(request_fun: request_fun)
  end

  describe "build_chat_request/1" do
    test "builds a native payload with num_ctx and tool names" do
      request = %Viber.API.MessageRequest{
        model: "ollama:qwen3.8:latest",
        max_tokens: 1024,
        system: "be helpful",
        stream: true,
        provider_overrides: %{num_ctx: 65_536},
        messages: [
          %Viber.API.InputMessage{role: "user", content: [%{type: "text", text: "pwd?"}]},
          %Viber.API.InputMessage{
            role: "assistant",
            content: [
              %{type: "tool_use", id: "call_1", name: "bash", input: %{"command" => "pwd"}}
            ]
          },
          %Viber.API.InputMessage{
            role: "user",
            content: [
              %{
                type: "tool_result",
                tool_use_id: "call_1",
                content: [%{type: "text", text: "/tmp"}],
                is_error: true
              }
            ]
          }
        ]
      }

      payload = Ollama.build_chat_request(request)

      assert payload.model == "qwen3.8:latest"
      assert payload.options == %{num_ctx: 65_536, num_predict: 1024}

      assert [
               %{role: "system", content: "be helpful"},
               %{role: "user", content: "pwd?"},
               %{
                 role: "assistant",
                 content: "",
                 tool_calls: [
                   %{id: "call_1", function: %{name: "bash", arguments: %{"command" => "pwd"}}}
                 ]
               },
               tool
             ] = payload.messages

      assert tool == %{role: "tool", tool_call_id: "call_1", tool_name: "bash", content: "/tmp"}
    end

    test "falls back to the default num_ctx" do
      request = %Viber.API.MessageRequest{model: "ollama:llama3", max_tokens: 0, messages: []}

      assert Ollama.build_chat_request(request).options == %{num_ctx: Ollama.default_num_ctx()}
    end
  end

  describe "stream_events_from_chunks/3" do
    test "emits text deltas and usage" do
      chunks = [
        %{"model" => "llama3", "message" => %{"role" => "assistant", "content" => "Hel"}},
        %{"model" => "llama3", "message" => %{"role" => "assistant", "content" => "lo"}},
        %{
          "model" => "llama3",
          "message" => %{"role" => "assistant", "content" => ""},
          "done" => true,
          "done_reason" => "stop",
          "prompt_eval_count" => 12,
          "eval_count" => 3
        }
      ]

      events = Ollama.stream_events_from_chunks("llama3", chunks)

      assert {:message_start, _} = hd(events)

      text =
        for {:content_block_delta, 0, %{type: "text_delta", text: t}} <- events, into: "", do: t

      assert text == "Hello"

      assert Enum.any?(events, fn
               {:message_delta, %{"stop_reason" => "end_turn"}, %Viber.API.Usage{} = usage} ->
                 usage.input_tokens == 12 and usage.output_tokens == 3

               _ ->
                 false
             end)
    end

    test "emits tool calls with a tool_use stop reason" do
      chunks = [
        %{
          "model" => "llama3",
          "message" => %{
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [
              %{"function" => %{"name" => "bash", "arguments" => %{"command" => "pwd"}}}
            ]
          }
        },
        %{
          "model" => "llama3",
          "message" => %{"content" => ""},
          "done" => true,
          "done_reason" => "stop"
        }
      ]

      events = Ollama.stream_events_from_chunks("llama3", chunks)

      assert Enum.any?(
               events,
               &match?({:content_block_start, _, %{type: "tool_use", name: "bash"}}, &1)
             )

      json =
        for {:content_block_delta, _, %{type: "input_json_delta", partial_json: j}} <- events,
            into: "",
            do: j

      assert Jason.decode!(json) == %{"command" => "pwd"}
      assert Enum.any?(events, &match?({:message_delta, %{"stop_reason" => "tool_use"}, _}, &1))
    end

    test "converts error chunks into a stream error with a context hint" do
      events =
        Ollama.stream_events_from_chunks(
          "llama3",
          [%{"error" => "no user query found in messages"}], num_ctx: 4096)

      assert Enum.any?(events, fn
               {:stream_error, message} -> message =~ "ollamaNumCtx" and message =~ "4096"
               _ -> false
             end)
    end
  end

  test "context_hint/2 leaves unrelated messages alone" do
    assert Ollama.context_hint("model not found", 4096) == "model not found"
  end
end
