defmodule Viber.Gateway do
  @moduledoc """
  Public API for the Gateway layer.

  The Gateway routes inbound messages from external chat channels (Discord,
  Telegram, …) to persistent Viber sessions, and sends replies or proactive
  messages back out through the same or any other registered adapter.

  ## Quick start

  1. Set Discord credentials in your config:

     ```elixir
     # config/runtime.exs
     config :viber, :discord,
       bot_token:      System.get_env("DISCORD_BOT_TOKEN"),
       public_key:     System.get_env("DISCORD_PUBLIC_KEY"),
       application_id: System.get_env("DISCORD_APPLICATION_ID")
     ```

  2. Ensure `start_server: true` is set so Bandit starts and exposes
     `POST /gateway/discord`.

  3. In the Discord developer portal set the Interactions Endpoint URL to
     `https://<your-host>/gateway/discord`.

  The `/viber` slash command is registered automatically on startup.

  ## Proactive outbound

      Viber.Gateway.send_to_channel(:discord, "1234567890", "Hello!")
      Viber.Gateway.broadcast("Viber is restarting…")
  """

  alias Viber.Gateway.Router

  @doc "Send a message to a specific channel on a specific adapter."
  @spec send_to_channel(atom(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate send_to_channel(adapter_id, channel_id, text, opts \\ []), to: Router

  @doc "Broadcast a message to every channel that has had inbound traffic."
  @spec broadcast(String.t()) :: :ok
  defdelegate broadcast(text), to: Router

  @doc "Return all `{adapter_id, channel_id}` pairs with recorded presence."
  @spec known_channels() :: [{atom(), String.t()}]
  defdelegate known_channels(), to: Router

  @doc "Manually register an adapter at runtime."
  @spec register_adapter(atom(), module(), map()) :: :ok
  defdelegate register_adapter(adapter_id, module, config), to: Router
end
