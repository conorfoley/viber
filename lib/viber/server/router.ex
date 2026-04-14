defmodule Viber.Server.Router do
  @moduledoc """
  Plug router providing REST and SSE endpoints for Viber.
  """

  use Plug.Router

  plug(Viber.Server.CORSPlug)
  plug(:match)
  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason,
    body_reader: {Viber.Server.BodyReader, :read_body, []}
  )
  plug(:dispatch)

  forward("/gateway", to: Viber.Gateway.WebhookRouter)

  post "/sessions" do
    case Viber.Server.SessionHandler.create_session(conn.body_params) do
      {:ok, session} ->
        send_json(conn, 201, session)

      {:error, reason} ->
        send_json(conn, 500, %{error: inspect(reason)})
    end
  end

  post "/sessions/:id/message" do
    case Viber.Server.SessionHandler.get_session(id) do
      {:ok, _pid} ->
        Viber.Server.SSE.stream(conn, id, conn.body_params)

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Session not found"})
    end
  end

  get "/sessions/:id/events" do
    case Viber.Server.SessionHandler.get_session(id) do
      {:ok, _pid} ->
        send_json(conn, 200, %{
          status: "ok",
          message: "Use POST /sessions/:id/message to send a message and stream events"
        })

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Session not found"})
    end
  end

  get "/health" do
    send_json(conn, 200, %{status: "ok"})
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
