defmodule Viber.Server.CORSPlug do
  @moduledoc """
  Simple CORS plug allowing cross-origin requests from browser extensions.
  """

  import Plug.Conn

  @behaviour Plug

  @allow_methods "GET, POST, PUT, DELETE, OPTIONS"
  @allow_headers "content-type, last-event-id, authorization"
  @expose_headers "last-event-id"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "OPTIONS"} = conn, _opts) do
    conn
    |> put_cors_headers()
    |> send_resp(200, "")
    |> halt()
  end

  def call(conn, _opts) do
    put_cors_headers(conn)
  end

  defp put_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", @allow_methods)
    |> put_resp_header("access-control-allow-headers", @allow_headers)
    |> put_resp_header("access-control-expose-headers", @expose_headers)
  end
end
