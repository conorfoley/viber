defmodule Viber.Gateway.Discord.Adapter do
  @moduledoc """
  Discord channel adapter implementing `Viber.Gateway.Adapter`.

  ## Outbound routing

  When `opts[:reply_context]` contains an `:interaction_token` and
  `:application_id`, the response is sent as an interaction followup message
  (for slash command replies). Otherwise the bot posts directly to the channel
  using the bot token.

  ## Text chunking

  Discord enforces a 2,000-character message limit. Responses longer than
  `@max_chunk` characters are split on grapheme boundaries and sent as
  sequential messages.
  """

  @behaviour Viber.Gateway.Adapter

  alias Viber.Gateway.Discord.Client

  @max_chunk 1_900

  @impl true
  def adapter_id, do: :discord

  @impl true
  def send_message(config, channel_id, text, opts) do
    chunks = chunk_text(text)

    case Keyword.get(opts, :reply_context) do
      %{interaction_token: token, application_id: app_id}
      when is_binary(token) and is_binary(app_id) ->
        send_interaction_followup(app_id, token, chunks)

      _ ->
        send_to_channel(config, channel_id, chunks)
    end
  end

  @impl true
  def typing_indicator(config, channel_id) do
    Client.trigger_typing(config.bot_token, channel_id)
  end

  @spec register_commands(map()) :: :ok | {:error, term()}
  def register_commands(config) do
    command = %{
      name: "viber",
      description: "Chat with Viber AI assistant",
      options: [
        %{
          type: 3,
          name: "message",
          description: "Your message to Viber",
          required: true
        }
      ]
    }

    Client.register_global_command(config.bot_token, config.application_id, command)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp chunk_text(text) when byte_size(text) <= @max_chunk, do: [text]

  defp chunk_text(text) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(@max_chunk)
    |> Enum.map(&Enum.join/1)
  end

  defp send_interaction_followup(_app_id, _token, []), do: :ok

  defp send_interaction_followup(app_id, token, [first | rest]) do
    with :ok <- Client.create_followup(app_id, token, first) do
      Enum.reduce_while(rest, :ok, fn chunk, _acc ->
        case Client.create_followup(app_id, token, chunk) do
          :ok -> {:cont, :ok}
          {:error, _} = err -> {:halt, err}
        end
      end)
    end
  end

  defp send_to_channel(_config, _channel_id, []), do: :ok

  defp send_to_channel(config, channel_id, [first | rest]) do
    with :ok <- Client.send_channel_message(config.bot_token, channel_id, first) do
      Enum.reduce_while(rest, :ok, fn chunk, _acc ->
        case Client.send_channel_message(config.bot_token, channel_id, chunk) do
          :ok -> {:cont, :ok}
          {:error, _} = err -> {:halt, err}
        end
      end)
    end
  end
end
