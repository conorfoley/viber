defmodule Viber.Server.BodyReader do
  @moduledoc """
  Custom body reader for `Plug.Parsers` that caches the raw request body in
  `conn.private[:raw_body]` before it is consumed by the parser.

  This is required so that webhook handlers (e.g. Discord) can read the raw
  body for cryptographic signature verification even after `Plug.Parsers` has
  already decoded the JSON into `conn.body_params`.

  Configure in `Plug.Parsers`:

      plug Plug.Parsers,
        parsers: [:json],
        json_decoder: Jason,
        body_reader: {Viber.Server.BodyReader, :read_body, []}
  """

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = Plug.Conn.put_private(conn, :raw_body, body)
        {:ok, body, conn}

      {:more, partial, conn} ->
        existing = conn.private[:raw_body] || ""
        conn = Plug.Conn.put_private(conn, :raw_body, existing <> partial)
        {:more, partial, conn}

      other ->
        other
    end
  end
end
