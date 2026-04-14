defmodule Viber.Gateway.WebhookRouter do
  @moduledoc """
  Plug router for all Gateway inbound webhooks.

  This router intentionally has **no `Plug.Parsers`** in its pipeline.
  Each webhook handler reads the raw body itself so it can perform
  cryptographic signature verification before decoding any JSON.

  Mounted at `/gateway` in `Viber.Server.Router` via `forward/2`.
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/discord" do
    Viber.Gateway.Discord.Webhook.call(conn, [])
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
