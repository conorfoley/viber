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
    rev_events = []

    {rev_events, state} =
      if not state.message_started do
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

        {[event | rev_events], %{state | message_started: true}}
      else
        {rev_events, state}
      end

    state =
      case chunk["usage"] do
        %{"prompt_tokens" => pt, "completion_tokens" => ct} ->
          %{state | usage: %Usage{input_tokens: pt, output_tokens: ct}}

        _ ->
          state
      end

    choices = chunk["choices"] || []

    {rev_events, state} =
      Enum.reduce(choices, {rev_events, state}, fn choice, {evts, st} ->
        delta = choice["delta"] || %{}

        {evts, st} =
          case delta["content"] do
            nil ->
              {evts, st}

            "" ->
              {evts, st}

            text ->
              if not st.text_started do
                delta_event = {:content_block_delta, 0, %{type: "text_delta", text: text}}
                start_event = {:content_block_start, 0, %{type: "text", text: ""}}
                {[delta_event, start_event | evts], %{st | text_started: true}}
              else
                delta_event = {:content_block_delta, 0, %{type: "text_delta", text: text}}
                {[delta_event | evts], st}
              end
          end

        tool_calls = delta["tool_calls"] || []

        {evts, st} =
          Enum.reduce(tool_calls, {evts, st}, fn tc, {e, s} ->
            idx = tc["index"] || 0

            existing =
              Map.get(s.tool_calls, idx, %{
                id: nil,
                name: nil,
                arguments: "",
                started: false,
                stopped: false
              })

            argument_delta = get_in(tc, ["function", "arguments"])

            existing =
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

            block_index = idx + 1

            {e, existing} =
              if not existing.started and existing.name do
                start =
                  {:content_block_start, block_index,
                   %{
                     type: "tool_use",
                     id: existing.id || "tool_call_#{idx}",
                     name: existing.name,
                     input: %{}
                   }}

                {[start | e], %{existing | started: true}}
              else
                {e, existing}
              end

            e =
              if existing.started and is_binary(argument_delta) and argument_delta != "" do
                delta_event =
                  {:content_block_delta, block_index,
                   %{type: "input_json_delta", partial_json: argument_delta}}

                [delta_event | e]
              else
                e
              end

            s = %{s | tool_calls: Map.put(s.tool_calls, idx, existing)}
            {e, s}
          end)

        st =
          case choice["finish_reason"] do
            nil -> st
            reason -> %{st | stop_reason: OpenAICompat.normalize_finish_reason(reason)}
          end

        {evts, st}
      end)

    {Enum.reverse(rev_events), state}
  end

  @spec finish(t()) :: [term()]
  def finish(%__MODULE__{} = state) do
    if state.finished or not state.message_started do
      []
    else
      rev_events = []

      rev_events =
        if state.text_started and not state.text_finished do
          [{:content_block_stop, 0} | rev_events]
        else
          rev_events
        end

      rev_events =
        Enum.reduce(state.tool_calls, rev_events, fn {idx, tc}, evts ->
          block_index = idx + 1

          evts =
            if not tc.started and tc.name do
              start =
                {:content_block_start, block_index,
                 %{type: "tool_use", id: tc.id || "tool_call_#{idx}", name: tc.name, input: %{}}}

              [start | evts]
            else
              evts
            end

          if (tc.started or tc.name != nil) and not tc.stopped do
            [{:content_block_stop, block_index} | evts]
          else
            evts
          end
        end)

      usage = state.usage || %Usage{input_tokens: 0, output_tokens: 0}

      Enum.reverse(rev_events) ++
        [
          {:message_delta,
           %{"stop_reason" => state.stop_reason || "end_turn", "stop_sequence" => nil}, usage},
          :message_stop
        ]
    end
  end

  defp non_empty(""), do: nil
  defp non_empty(nil), do: nil
  defp non_empty(s), do: s
end
