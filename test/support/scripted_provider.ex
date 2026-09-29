defmodule Viber.ScriptedProvider do
  @moduledoc """
  A `Viber.API.Provider` test double driven by the calling process.

  `script/1` stores the responses for `send_message/1` and `script_stream/1`
  the turns for `stream_message/1` in the process dictionary, and every
  request is recorded, so it only works when the provider is called from
  the test process itself (e.g. `Viber.Runtime.Predict` or a sequential
  `Viber.Runtime.Conversation` run with `provider_module:`).

  A stream turn is a list of `{:text, text}` and
  `{:tool, id, name, input_map}` blocks.
  """

  @behaviour Viber.API.Provider

  alias Viber.API.{MessageResponse, Usage}

  @spec script([term()]) :: :ok
  def script(responses) do
    Process.put(:scripted_responses, responses)
    Process.put(:scripted_requests, [])
    :ok
  end

  @spec script_stream([[tuple()]]) :: :ok
  def script_stream(turns) do
    Process.put(:scripted_turns, turns)
    Process.put(:scripted_requests, [])
    :ok
  end

  @spec requests() :: [Viber.API.MessageRequest.t()]
  def requests, do: Enum.reverse(Process.get(:scripted_requests, []))

  @spec response([map()]) :: {:ok, MessageResponse.t()}
  def response(content) do
    {:ok,
     %MessageResponse{
       id: "msg",
       type: "message",
       role: "assistant",
       content: content,
       model: "test",
       usage: %Usage{input_tokens: 1, output_tokens: 1}
     }}
  end

  @impl true
  def send_message(request) do
    Process.put(:scripted_requests, [request | Process.get(:scripted_requests, [])])

    case Process.get(:scripted_responses, []) do
      [next | rest] ->
        Process.put(:scripted_responses, rest)
        next

      [] ->
        {:error, %Viber.API.Error{type: :api, message: "no more scripted responses"}}
    end
  end

  @impl true
  def stream_message(request) do
    Process.put(:scripted_requests, [request | Process.get(:scripted_requests, [])])

    case Process.get(:scripted_turns, []) do
      [turn | rest] ->
        Process.put(:scripted_turns, rest)
        {:ok, stream_events(turn)}

      [] ->
        {:error, %Viber.API.Error{type: :api, message: "no more scripted turns"}}
    end
  end

  defp stream_events(turn) do
    usage = %Usage{input_tokens: 1, output_tokens: 1}

    blocks =
      turn
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {{:text, text}, idx} ->
          [
            {:content_block_start, idx, %{type: "text", text: ""}},
            {:content_block_delta, idx, %{type: "text_delta", text: text}},
            {:content_block_stop, idx}
          ]

        {{:tool, id, name, input}, idx} ->
          [
            {:content_block_start, idx, %{type: "tool_use", id: id, name: name}},
            {:content_block_delta, idx,
             %{type: "input_json_delta", partial_json: Jason.encode!(input)}},
            {:content_block_stop, idx}
          ]
      end)

    start =
      {:message_start,
       %MessageResponse{
         id: "msg",
         type: "message",
         role: "assistant",
         content: [],
         model: "test",
         usage: usage
       }}

    [start | blocks] ++ [{:message_delta, %{"stop_reason" => "end_turn"}, usage}, :message_stop]
  end
end
