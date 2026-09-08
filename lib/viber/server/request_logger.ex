defmodule Viber.Server.RequestLogger do
  @moduledoc """
  Plug that logs every incoming HTTP request for debugging.
  Uses both IO.puts (always visible in terminal) and Logger (file handler).
  """

  require Logger

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    line = "HTTP #{conn.method} #{conn.request_path}"
    IO.puts("[RequestLogger] #{line}")
    Logger.info("RequestLogger: #{line}")
    conn
  end
end
