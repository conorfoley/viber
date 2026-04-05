defmodule Viber.Runtime.Conversation.StreamAccumulator do
  @moduledoc """
  Accumulates stream events into a complete response.
  """

  @type block_state ::
          %{type: :text, text: String.t()}
          | %{type: :tool_use, id: String.t(), name: String.t(), input: String.t()}
          | %{type: :thinking, text: String.t()}
          | %{type: :unknown}

  @type t :: %__MODULE__{
          response: Viber.API.MessageResponse.t() | nil,
          blocks: %{non_neg_integer() => block_state()},
          current_usage: Viber.API.Usage.t() | nil,
          stream_error: term() | nil
        }

  defstruct response: nil, blocks: %{}, current_usage: nil, stream_error: nil
end
