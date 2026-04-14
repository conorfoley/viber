defmodule Viber.Gateway.Discord.Webhook do
  @moduledoc """
  Plug handler for Discord interaction webhooks.

  Discord sends a POST to this handler for every interaction (ping, slash
  command, etc.). The raw request body must be read here — before any JSON
  parser consumes it — so that the Ed25519 signature can be verified.

  ## Response strategy

  | Interaction type | Immediate HTTP response |
  |------------------|------------------------|
  | PING (type 1)    | `{"type": 1}` — PONG   |
  | COMMAND (type 2) | `{"type": 5}` — deferred response ("is thinking…") |

  After returning the deferred response the interaction is handed off
  asynchronously to `Viber.Gateway.Router`. When the conversation finishes,
  the router calls the Discord adapter which posts a followup message via the
  REST API using the interaction token stored in `message.metadata`.
  """

  import Plug.Conn

  require Logger

  alias Viber.Gateway.Discord.EventParser
  alias Viber.Gateway.Router

  def init(opts), do: opts

  def call(conn, _opts) do
    raw_body = conn.private[:raw_body] || ""

    with :ok <- verify_signature(conn, raw_body),
         {:ok, payload} <- Jason.decode(raw_body) do
      handle_interaction(conn, payload)
    else
      {:error, :invalid_signature} ->
        Logger.warning("Discord webhook: invalid signature")
        conn |> send_resp(401, "Invalid request signature") |> halt()

      {:error, reason} ->
        Logger.warning("Discord webhook: bad request #{inspect(reason)}")
        conn |> send_resp(400, "Bad request") |> halt()
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp handle_interaction(conn, payload) do
    case EventParser.parse(payload) do
      {:pong} ->
        send_json(conn, 200, %{type: 1})

      {:ok, message} ->
        Router.inbound(message)
        send_json(conn, 200, %{type: 5})

      {:error, :unsupported_event} ->
        send_resp(conn, 200, "")

      {:error, :missing_text} ->
        send_json(conn, 200, %{
          type: 4,
          data: %{content: "Please provide a message. Usage: `/viber message:<your text>`"}
        })
    end
  end

  defp verify_signature(conn, body) do
    public_key = discord_config(:public_key)

    sig_header = get_req_header(conn, "x-signature-ed25519")
    ts_header = get_req_header(conn, "x-signature-timestamp")

    with true <- is_binary(public_key),
         [sig_hex | _] <- sig_header,
         [timestamp | _] <- ts_header,
         {:ok, signature} <- Base.decode16(String.upcase(sig_hex)),
         {:ok, pub_key_bytes} <- Base.decode16(String.upcase(public_key)) do
      message = timestamp <> body

      if :crypto.verify(:eddsa, :none, message, signature, [pub_key_bytes, :ed25519]) do
        :ok
      else
        {:error, :invalid_signature}
      end
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp discord_config(key) do
    Application.get_env(:viber, :discord, []) |> Keyword.get(key)
  end
end
