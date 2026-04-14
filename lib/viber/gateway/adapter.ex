defmodule Viber.Gateway.Adapter do
  @moduledoc """
  Behaviour for channel adapters in the Gateway layer.

  Each adapter translates between a specific chat platform (Discord, Telegram, etc.)
  and the normalized `Viber.Gateway.Message` format, and knows how to send
  replies back to that platform.
  """

  @type config :: map()
  @type channel_id :: String.t()
  @type send_opts :: keyword()

  @doc "Unique atom identifying this adapter."
  @callback adapter_id() :: atom()

  @doc """
  Send a text message to the given channel.

  `opts` may include:
  - `reply_context: map()` — adapter-specific data needed to reply (e.g. Discord interaction token)
  """
  @callback send_message(config(), channel_id(), text :: String.t(), send_opts()) ::
              :ok | {:error, term()}

  @doc "Show a typing/processing indicator in the channel (optional)."
  @callback typing_indicator(config(), channel_id()) :: :ok | {:error, term()}

  @optional_callbacks [typing_indicator: 2]
end
