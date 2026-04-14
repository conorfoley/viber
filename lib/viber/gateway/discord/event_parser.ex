defmodule Viber.Gateway.Discord.EventParser do
  @moduledoc """
  Parses raw Discord interaction payloads into `Viber.Gateway.Message` structs.

  Discord interaction types handled:
  - `1` — PING (used during URL verification in the developer portal)
  - `2` — APPLICATION_COMMAND (slash commands)

  All other types return `{:error, :unsupported_event}`.
  """

  alias Viber.Gateway.Message

  @type parse_result ::
          {:pong}
          | {:ok, Message.t()}
          | {:error, :unsupported_event | :missing_text}

  @spec parse(map()) :: parse_result()
  def parse(%{"type" => 1}) do
    {:pong}
  end

  def parse(%{"type" => 2} = payload) do
    user_id =
      get_in(payload, ["member", "user", "id"]) ||
        get_in(payload, ["user", "id"]) ||
        "unknown"

    channel_id = payload["channel_id"] || "unknown"
    interaction_token = payload["token"]
    application_id = payload["application_id"]
    guild_id = payload["guild_id"]

    case extract_text(payload) do
      {:ok, text} ->
        msg = %Message{
          id: payload["id"],
          adapter_id: :discord,
          channel_id: channel_id,
          user_id: user_id,
          text: text,
          metadata: %{
            interaction_token: interaction_token,
            application_id: application_id,
            guild_id: guild_id,
            type: :slash_command
          },
          timestamp: DateTime.utc_now()
        }

        {:ok, msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def parse(_payload) do
    {:error, :unsupported_event}
  end

  defp extract_text(%{"data" => data}) do
    options = data["options"] || []

    text =
      Enum.find_value(options, fn
        %{"name" => name, "value" => value}
        when name in ["message", "input", "prompt", "text"] and is_binary(value) ->
          value

        _ ->
          nil
      end)

    case text do
      nil when options == [] -> {:error, :missing_text}
      nil -> {:ok, data["name"] || ""}
      t -> {:ok, t}
    end
  end

  defp extract_text(_), do: {:error, :missing_text}
end
