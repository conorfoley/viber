defmodule Viber.Gateway.Message do
  @moduledoc """
  Normalized inbound message from any channel adapter.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          adapter_id: atom(),
          channel_id: String.t(),
          user_id: String.t(),
          text: String.t(),
          metadata: map(),
          timestamp: DateTime.t() | nil
        }

  @enforce_keys [:id, :adapter_id, :channel_id, :user_id, :text]
  defstruct [
    :id,
    :adapter_id,
    :channel_id,
    :user_id,
    :text,
    metadata: %{},
    timestamp: nil
  ]
end
