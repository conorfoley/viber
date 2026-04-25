defmodule Viber.Runtime.Event.Legacy do
  @moduledoc """
  Backwards-compatibility helpers between the legacy tuple event representation
  and `Viber.Runtime.Event` structs.

  This module exists to ease migration while M1–M2 land. New code should emit
  and consume `%Viber.Runtime.Event{}` directly. Remove this module after M2
  (see `agent_docs/frontend-portability-plan.md`).
  """

  alias Viber.Runtime.Event
  alias Viber.Runtime.Usage

  @type tuple_event ::
          {:text_delta, String.t()}
          | {:thinking_delta, String.t()}
          | {:tool_use_start, String.t(), String.t()}
          | {:tool_result, String.t(), String.t(), boolean()}
          | {:turn_complete, Usage.t()}
          | {:error, String.t()}
          | {:interrupted, String.t()}

  @spec to_tuple(Event.t()) :: tuple_event() | :unknown
  def to_tuple(%Event{type: :text_delta, payload: %{text: t}}), do: {:text_delta, t}
  def to_tuple(%Event{type: :thinking_delta, payload: %{text: t}}), do: {:thinking_delta, t}

  def to_tuple(%Event{type: :tool_use_start, payload: %{name: n, id: id}}),
    do: {:tool_use_start, n, id}

  def to_tuple(%Event{
        type: :tool_result,
        payload: %{name: n, output: o, is_error: e}
      }),
      do: {:tool_result, n, o, e}

  def to_tuple(%Event{type: :turn_complete, payload: %{usage: %Usage{} = u}}),
    do: {:turn_complete, u}

  def to_tuple(%Event{type: :error, payload: %{message: m}}), do: {:error, m}
  def to_tuple(%Event{type: :interrupted, payload: %{message: m}}), do: {:interrupted, m}
  def to_tuple(%Event{}), do: :unknown

  @spec from_tuple(tuple_event()) :: Event.t()
  def from_tuple({:text_delta, text}), do: Event.new(:text_delta, %{text: text})
  def from_tuple({:thinking_delta, text}), do: Event.new(:thinking_delta, %{text: text})

  def from_tuple({:tool_use_start, name, id}),
    do: Event.new(:tool_use_start, %{name: name, id: id})

  def from_tuple({:tool_result, name, output, is_error}),
    do: Event.new(:tool_result, %{name: name, id: nil, output: output, is_error: is_error})

  def from_tuple({:turn_complete, %Usage{} = usage}),
    do: Event.new(:turn_complete, %{usage: usage})

  def from_tuple({:error, message}), do: Event.new(:error, %{message: message})
  def from_tuple({:interrupted, message}), do: Event.new(:interrupted, %{message: message})
end
