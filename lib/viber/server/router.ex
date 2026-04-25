defmodule Viber.Server.Router do
  @moduledoc """
  Plug router providing REST and SSE endpoints for Viber.

  The wire protocol (event envelope + payloads) is defined in
  `Viber.Runtime.Event`; the machine-readable schema is served at
  `GET /schema/events`.
  """

  use Plug.Router

  alias Viber.Server.SessionHandler

  plug(Viber.Server.CORSPlug)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason,
    body_reader: {Viber.Server.BodyReader, :read_body, []}
  )

  plug(:dispatch)

  forward("/gateway", to: Viber.Gateway.WebhookRouter)

  # --- Sessions ----------------------------------------------------------

  get "/sessions" do
    send_json(conn, 200, %{sessions: SessionHandler.list_sessions()})
  end

  post "/sessions" do
    case SessionHandler.create_session(conn.body_params) do
      {:ok, session} -> send_json(conn, 201, session)
      {:error, reason} -> send_json(conn, 500, %{error: inspect(reason)})
    end
  end

  get "/sessions/:id" do
    case SessionHandler.session_info(id) do
      {:ok, info} -> send_json(conn, 200, info)
      {:error, :not_found} -> send_json(conn, 404, %{error: "Session not found"})
    end
  end

  delete "/sessions/:id" do
    purge? = conn.query_params["purge"] in ["1", "true", "yes"]

    case SessionHandler.delete_session(id, purge: purge?) do
      :ok -> send_json(conn, 200, %{ok: true, purged: purge?})
      {:error, :not_found} -> send_json(conn, 404, %{error: "Session not found"})
    end
  end

  get "/sessions/:id/messages" do
    limit = parse_int(conn.query_params["limit"], 100)
    offset = parse_int(conn.query_params["offset"], 0)

    case SessionHandler.list_messages(id, limit: limit, offset: offset) do
      {:ok, payload} -> send_json(conn, 200, payload)
      {:error, :not_found} -> send_json(conn, 404, %{error: "Session not found"})
    end
  end

  post "/sessions/:id/resume" do
    case SessionHandler.resume_session(id) do
      {:ok, payload} -> send_json(conn, 200, payload)
      {:error, :already_active} -> send_json(conn, 409, %{error: "session already active"})
      {:error, :not_found} -> send_json(conn, 404, %{error: "Session not found"})
      {:error, reason} -> send_json(conn, 500, %{error: inspect(reason)})
    end
  end

  post "/sessions/:id/interrupt" do
    case SessionHandler.interrupt(id) do
      :ok -> send_json(conn, 202, %{ok: true})
      {:error, :not_found} -> send_json(conn, 404, %{error: "Session not found"})
    end
  end

  post "/sessions/:id/message" do
    case SessionHandler.get_session(id) do
      {:ok, _pid} ->
        Viber.Server.SSE.stream(conn, id, conn.body_params)

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Session not found"})
    end
  end

  get "/sessions/:id/events" do
    case SessionHandler.get_session(id) do
      {:ok, _pid} ->
        send_json(conn, 200, %{
          status: "ok",
          message: "Use POST /sessions/:id/message to send a message and stream events"
        })

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Session not found"})
    end
  end

  post "/sessions/:id/commands" do
    name = conn.body_params["name"]
    args = List.wrap(conn.body_params["args"] || [])
    opts = conn.body_params["opts"] || %{}

    cond do
      not is_binary(name) or name == "" ->
        send_json(conn, 422, %{error: "missing 'name'"})

      not Enum.all?(args, &is_binary/1) ->
        send_json(conn, 422, %{error: "'args' must be a list of strings"})

      true ->
        case SessionHandler.invoke_command(id, name, args, opts) do
          {:ok, result} ->
            send_json(conn, 200, result)

          {:error, :not_found} ->
            send_json(conn, 404, %{error: "Session not found"})

          {:error, {:unknown_command, n}} ->
            send_json(conn, 404, %{error: "unknown command: #{n}"})

          {:error, {:handler_crash, msg}} ->
            send_json(conn, 500, %{error: "handler crashed: #{msg}"})

          {:error, reason} when is_binary(reason) ->
            send_json(conn, 422, %{error: reason})

          {:error, reason} ->
            send_json(conn, 422, %{error: inspect(reason)})
        end
    end
  end

  post "/sessions/:id/permissions/:request_id" do
    case SessionHandler.get_session(id) do
      {:ok, _pid} ->
        case decode_decision(conn.body_params["decision"]) do
          {:ok, decision} ->
            case Viber.Runtime.Permissions.Broker.resolve(request_id, decision, session_id: id) do
              :ok ->
                send_json(conn, 200, %{ok: true})

              {:error, :not_found} ->
                send_json(conn, 404, %{error: "permission request not found"})

              {:error, :session_mismatch} ->
                send_json(conn, 409, %{error: "permission request belongs to another session"})
            end

          :error ->
            send_json(conn, 422, %{
              error: "invalid decision; expected one of allow|deny|always_allow"
            })
        end

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Session not found"})
    end
  end

  # --- Metadata ----------------------------------------------------------

  get "/models" do
    aliases = Viber.API.Client.model_aliases()

    canonical =
      aliases
      |> Map.values()
      |> Enum.uniq()
      |> Enum.sort()

    send_json(conn, 200, %{
      aliases: aliases,
      canonical: canonical
    })
  end

  get "/toolsets" do
    send_json(conn, 200, %{toolsets: Viber.Tools.Registry.list_toolsets()})
  end

  get "/schema/events" do
    send_json(conn, 200, Viber.Runtime.Event.schema())
  end

  get "/health" do
    send_json(conn, 200, %{status: "ok"})
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp decode_decision("allow"), do: {:ok, :allow}
  defp decode_decision("deny"), do: {:ok, :deny}
  defp decode_decision("always_allow"), do: {:ok, :always_allow}
  defp decode_decision(_), do: :error

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
