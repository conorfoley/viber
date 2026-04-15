defmodule Viber.API.Providers.OpenAIStreamState do
  @moduledoc """
  Streaming state machine that translates OpenAI delta-based SSE chunks
  into Anthropic-style content block events.
  """

  alias Viber.API.{MessageResponse, Usage}
  alias Viber.API.Providers.OpenAICompat

  defstruct model: nil,
            message_started: false,
            text_started: false,
            text_finished: false,
            finished: false,
            stop_reason: nil,
            usage: nil,
            tool_calls: %{}

  @type t :: %__MODULE__{}

  @spec new(String.t()) :: t()
  def new(model), do: %__MODULE__{model: model}

  @spec events_from_chunks(String.t(), [map()]) :: [term()]
  def events_from_chunks(model, chunks) do
    {events, state} =
      Enum.reduce(chunks, {[], new(model)}, fn chunk, {acc, st} ->
        {new_events, new_state} = ingest(st, chunk)
        {acc ++ new_events, new_state}
      end)

    events ++ finish(state)
  end

  @spec ingest(t(), map()) :: {[term()], t()}
  def ingest(%__MODULE__{} = state, chunk) do
    {rev_events, state} = maybe_emit_message_start([], state, chunk)
    state = update_usage(state, chunk["usage"])
    choices = chunk["choices"] || []

    {rev_events, state} =
      Enum.reduce(choices, {rev_events, state}, fn choice, {evts, st} ->
        delta = choice["delta"] || %{}
        {evts, st} = process_text_delta(evts, st, delta["content"])
        {evts, st} = process_tool_call_deltas(evts, st, delta["tool_calls"] || [])
        st = process_finish_reason(st, choice["finish_reason"])
        {evts, st}
      end)

    {Enum.reverse(rev_events), state}
  end

  defp maybe_emit_message_start(evts, %{message_started: true} = state, _chunk),
    do: {evts, state}

  defp maybe_emit_message_start(evts, state, chunk) do
    event =
      {:message_start,
       %MessageResponse{
         id: chunk["id"],
         type: "message",
         role: "assistant",
         content: [],
         model: (chunk["model"] || state.model) |> non_empty() || state.model,
         usage: %Usage{input_tokens: 0, output_tokens: 0}
       }}

    {[event | evts], %{state | message_started: true}}
  end

  defp update_usage(state, %{"prompt_tokens" => pt, "completion_tokens" => ct}),
    do: %{state | usage: %Usage{input_tokens: pt, output_tokens: ct}}

  defp update_usage(state, _), do: state

  defp process_text_delta(evts, st, nil), do: {evts, st}
  defp process_text_delta(evts, st, ""), do: {evts, st}

  defp process_text_delta(evts, %{text_started: false} = st, text) do
    delta_event = {:content_block_delta, 0, %{type: "text_delta", text: text}}
    start_event = {:content_block_start, 0, %{type: "text", text: ""}}
    {[delta_event, start_event | evts], %{st | text_started: true}}
  end

  defp process_text_delta(evts, st, text) do
    delta_event = {:content_block_delta, 0, %{type: "text_delta", text: text}}
    {[delta_event | evts], st}
  end

  defp process_tool_call_deltas(evts, st, tool_calls) do
    Enum.reduce(tool_calls, {evts, st}, fn tc, {e, s} ->
      process_single_tool_call(e, s, tc)
    end)
  end

  @empty_tool_call %{id: nil, name: nil, arguments: "", started: false, stopped: false}

  defp process_single_tool_call(evts, state, tc) do
    idx = tc["index"] || 0
    existing = Map.get(state.tool_calls, idx, @empty_tool_call)
    argument_delta = get_in(tc, ["function", "arguments"])

    existing = merge_tool_call_fields(existing, tc, argument_delta)
    block_index = idx + 1

    {evts, existing} = maybe_emit_tool_start(evts, existing, idx, block_index)
    evts = maybe_emit_tool_argument_delta(evts, existing, argument_delta, block_index)

    state = %{state | tool_calls: Map.put(state.tool_calls, idx, existing)}
    {evts, state}
  end

  defp merge_tool_call_fields(existing, tc, argument_delta) do
    existing
    |> then(fn ex -> if tc["id"], do: %{ex | id: tc["id"]}, else: ex end)
    |> then(fn ex ->
      case get_in(tc, ["function", "name"]) do
        nil -> ex
        name -> %{ex | name: name}
      end
    end)
    |> then(fn ex ->
      case argument_delta do
        nil -> ex
        args -> %{ex | arguments: ex.arguments <> args}
      end
    end)
  end

  defp maybe_emit_tool_start(evts, %{started: false, name: name} = tc, idx, block_index)
       when not is_nil(name) do
    start =
      {:content_block_start, block_index,
       %{type: "tool_use", id: tc.id || "tool_call_#{idx}", name: name, input: %{}}}

    {[start | evts], %{tc | started: true}}
  end

  defp maybe_emit_tool_start(evts, tc, _idx, _block_index), do: {evts, tc}

  defp maybe_emit_tool_argument_delta(evts, %{started: true}, arg, block_index)
       when is_binary(arg) and arg != "" do
    delta_event =
      {:content_block_delta, block_index, %{type: "input_json_delta", partial_json: arg}}

    [delta_event | evts]
  end

  defp maybe_emit_tool_argument_delta(evts, _tc, _arg, _block_index), do: evts

  defp process_finish_reason(st, nil), do: st

  defp process_finish_reason(st, reason),
    do: %{st | stop_reason: OpenAICompat.normalize_finish_reason(reason)}

  @spec finish(t()) :: [term()]
  def finish(%__MODULE__{finished: true}), do: []
  def finish(%__MODULE__{message_started: false}), do: []

  def finish(%__MODULE__{} = state) do
    rev_events = finish_text_block([], state)
    rev_events = finish_tool_blocks(rev_events, state.tool_calls)
    usage = state.usage || %Usage{input_tokens: 0, output_tokens: 0}

    Enum.reverse(rev_events) ++
      [
        {:message_delta,
         %{"stop_reason" => state.stop_reason || "end_turn", "stop_sequence" => nil}, usage},
        :message_stop
      ]
  end

  defp finish_text_block(evts, %{text_started: true, text_finished: false}),
    do: [{:content_block_stop, 0} | evts]

  defp finish_text_block(evts, _state), do: evts

  defp finish_tool_blocks(evts, tool_calls) do
    Enum.reduce(tool_calls, evts, fn {idx, tc}, acc ->
      block_index = idx + 1
      acc = maybe_emit_late_tool_start(acc, tc, idx, block_index)
      maybe_emit_tool_stop(acc, tc, block_index)
    end)
  end

  defp maybe_emit_late_tool_start(evts, %{started: false, name: name} = tc, idx, block_index)
       when not is_nil(name) do
    start =
      {:content_block_start, block_index,
       %{type: "tool_use", id: tc.id || "tool_call_#{idx}", name: name, input: %{}}}

    [start | evts]
  end

  defp maybe_emit_late_tool_start(evts, _tc, _idx, _block_index), do: evts

  defp maybe_emit_tool_stop(evts, %{stopped: true}, _block_index), do: evts

  defp maybe_emit_tool_stop(evts, %{started: true}, block_index),
    do: [{:content_block_stop, block_index} | evts]

  defp maybe_emit_tool_stop(evts, %{name: name}, block_index) when not is_nil(name),
    do: [{:content_block_stop, block_index} | evts]

  defp maybe_emit_tool_stop(evts, _tc, _block_index), do: evts

  defp non_empty(""), do: nil
  defp non_empty(nil), do: nil
  defp non_empty(s), do: s
end
