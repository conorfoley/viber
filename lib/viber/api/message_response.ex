defmodule Viber.API.MessageResponse do
  @moduledoc """
  A complete (non-streaming) response from the LLM API.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          role: String.t(),
          content: [map()],
          model: String.t(),
          stop_reason: String.t() | nil,
          stop_sequence: String.t() | nil,
          usage: Viber.API.Usage.t(),
          request_id: String.t() | nil
        }

  @enforce_keys [:id, :type, :role, :content, :model, :usage]
  defstruct [
    :id,
    :type,
    :role,
    :content,
    :model,
    :stop_reason,
    :stop_sequence,
    :usage,
    :request_id
  ]
end
