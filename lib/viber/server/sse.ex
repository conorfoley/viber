defmodule Viber.Server.SSE do
  @moduledoc """
  Server-Sent Events streaming for conversation events.

  Consumes `%Viber.Runtime.Event{}` values and serializes them via
  `Viber.Runtime.Event.to_map/1` — the single source of truth for the wire
  protocol.
  """

  import Plug.Conn

  require Logger

  alias Viber.Runtime.Event

  @spec stream(Plug.Conn.t(), String.t(), map()) :: Plug.Conn.t()
  def stream(conn, session_id, params) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    caller = self()

    event_handler = fn event ->
      send(caller, {:sse_event, event})
      :ok
    end

    case Viber.Server.SessionHandler.send_message(session_id, params, event_handler) do
      {:ok, task_pid} ->
        Logger.info("SSE: stream started session=#{session_id} task=#{inspect(task_pid)}")
        monitor_ref = Process.monitor(task_pid)
        stream_loop(conn, session_id, monitor_ref)

      {:error, :not_found} ->
        send_sse_event(conn, Event.new(:error, %{message: "Session not found"}))
        conn
    end
  end

  defp stream_loop(conn, session_id, monitor_ref) do
    receive do
      {:sse_event, %Event{type: type} = event} ->
        Logger.debug("SSE: sending event=#{type} session=#{session_id}")

        case send_sse_event(conn, event) do
          {:ok, conn} ->
            if terminal?(type) do
              Logger.info("SSE: stream complete event=#{type} session=#{session_id}")
              Process.demonitor(monitor_ref, [:flush])
              conn
            else
              stream_loop(conn, session_id, monitor_ref)
            end

          {:error, reason} ->
            Logger.warning(
              "SSE: send error event=#{type} session=#{session_id} reason=#{inspect(reason)}"
            )

            Process.demonitor(monitor_ref, [:flush])
            conn
        end

      {:DOWN, ^monitor_ref, :process, _pid, reason} ->
        Logger.info("SSE: task down session=#{session_id} reason=#{inspect(reason)}")
        conn
    after
      300_000 ->
        Logger.warning("SSE: stream timeout session=#{session_id}")
        Process.demonitor(monitor_ref, [:flush])
        conn
    end
  end

  defp terminal?(:turn_complete), do: true
  defp terminal?(:error), do: true
  defp terminal?(:interrupted), do: true
  defp terminal?(_), do: false

  defp send_sse_event(conn, %Event{type: type} = event) do
    data = Jason.encode!(Event.to_map(event))
    payload = "event: #{Atom.to_string(type)}\ndata: #{data}\n\n"
    chunk(conn, payload)
  end
end
