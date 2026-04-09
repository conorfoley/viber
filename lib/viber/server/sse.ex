defmodule Viber.Server.SSE do
  @moduledoc """
  Server-Sent Events streaming for conversation events.
  """

  import Plug.Conn

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
        monitor_ref = Process.monitor(task_pid)
        stream_loop(conn, monitor_ref)

      {:error, :not_found} ->
        send_sse_event(conn, "error", %{message: "Session not found"})
        conn
    end
  end

  defp stream_loop(conn, monitor_ref) do
    receive do
      {:sse_event, {:text_delta, text}} ->
        case send_sse_event(conn, "text_delta", %{text: text}) do
          {:ok, conn} -> stream_loop(conn, monitor_ref)
          {:error, _} -> conn
        end

      {:sse_event, {:tool_use_start, name, id}} ->
        case send_sse_event(conn, "tool_use_start", %{name: name, id: id}) do
          {:ok, conn} -> stream_loop(conn, monitor_ref)
          {:error, _} -> conn
        end

      {:sse_event, {:tool_result, name, output, is_error}} ->
        case send_sse_event(conn, "tool_result", %{
               name: name,
               output: output,
               is_error: is_error
             }) do
          {:ok, conn} -> stream_loop(conn, monitor_ref)
          {:error, _} -> conn
        end

      {:sse_event, {:thinking_delta, text}} ->
        case send_sse_event(conn, "thinking_delta", %{text: text}) do
          {:ok, conn} -> stream_loop(conn, monitor_ref)
          {:error, _} -> conn
        end

      {:sse_event, {:turn_complete, usage}} ->
        send_sse_event(conn, "turn_complete", %{
          input_tokens: usage.input_tokens,
          output_tokens: usage.output_tokens
        })

        conn

      {:sse_event, {:error, message}} ->
        send_sse_event(conn, "error", %{message: message})
        conn

      {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
        conn
    after
      300_000 ->
        conn
    end
  end

  defp send_sse_event(conn, event_type, data) do
    payload = "event: #{event_type}\ndata: #{Jason.encode!(data)}\n\n"
    chunk(conn, payload)
  end
end
