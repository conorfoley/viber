defmodule Viber.Server.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Viber.Server.Router

  @opts Router.init([])

  test "GET /health returns 200" do
    conn = conn(:get, "/health") |> Router.call(@opts)
    assert conn.status == 200
    assert {:ok, body} = Jason.decode(conn.resp_body)
    assert body["status"] == "ok"
  end

  test "GET /unknown returns 404" do
    conn = conn(:get, "/unknown") |> Router.call(@opts)
    assert conn.status == 404
  end

  test "POST /sessions returns 201 with session id" do
    conn =
      conn(:post, "/sessions", %{})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 201
    assert {:ok, body} = Jason.decode(conn.resp_body)
    assert is_binary(body["id"])
  end

  test "POST /sessions/:id/message with invalid session returns 404" do
    conn =
      conn(:post, "/sessions/nonexistent/message", %{"message" => "hello"})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 404
  end
end
