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

  test "GET /sessions returns a list" do
    conn = conn(:get, "/sessions") |> Router.call(@opts)
    assert conn.status == 200
    assert {:ok, %{"sessions" => sessions}} = Jason.decode(conn.resp_body)
    assert is_list(sessions)
  end

  test "GET /sessions/:id with missing session returns 404" do
    conn = conn(:get, "/sessions/does-not-exist") |> Router.call(@opts)
    assert conn.status == 404
  end

  test "GET /sessions/:id/messages with missing session returns 404" do
    conn = conn(:get, "/sessions/does-not-exist/messages") |> Router.call(@opts)
    assert conn.status == 404
  end

  test "DELETE /sessions/:id on missing session returns 404" do
    conn = conn(:delete, "/sessions/does-not-exist") |> Router.call(@opts)
    assert conn.status == 404
  end

  test "POST /sessions/:id/interrupt with missing session returns 404" do
    conn = conn(:post, "/sessions/does-not-exist/interrupt") |> Router.call(@opts)
    assert conn.status == 404
  end

  test "POST /sessions/:id/resume with missing session returns error" do
    conn = conn(:post, "/sessions/does-not-exist/resume") |> Router.call(@opts)
    assert conn.status in [404, 500]
  end

  test "POST /sessions/:id/permissions/:rid on invalid session returns 404" do
    conn =
      conn(:post, "/sessions/nope/permissions/req-1", %{"decision" => "allow"})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 404
  end

  test "POST /sessions/:id/permissions/:rid with invalid decision returns 422" do
    {:ok, %{id: id}} = Viber.Server.SessionHandler.create_session(%{})

    conn =
      conn(:post, "/sessions/#{id}/permissions/req-1", %{"decision" => "bogus"})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 422
  end

  test "GET /models returns aliases + canonical" do
    conn = conn(:get, "/models") |> Router.call(@opts)
    assert conn.status == 200
    assert {:ok, body} = Jason.decode(conn.resp_body)
    assert is_map(body["aliases"])
    assert is_list(body["canonical"])
  end

  test "GET /toolsets returns toolsets" do
    conn = conn(:get, "/toolsets") |> Router.call(@opts)
    assert conn.status == 200
    assert {:ok, %{"toolsets" => ts}} = Jason.decode(conn.resp_body)
    assert is_list(ts)
  end

  test "GET /schema/events returns event schema" do
    conn = conn(:get, "/schema/events") |> Router.call(@opts)
    assert conn.status == 200
    assert {:ok, body} = Jason.decode(conn.resp_body)
    assert body["version"]
    assert is_map(body["types"])
  end

  test "POST /sessions/:id/commands /help returns text" do
    {:ok, %{id: id}} = Viber.Server.SessionHandler.create_session(%{})

    conn =
      conn(:post, "/sessions/#{id}/commands", %{"name" => "help", "args" => []})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 200
    assert {:ok, body} = Jason.decode(conn.resp_body)
    assert body["name"] == "help"
    assert is_binary(body["text"])
    assert is_list(body["events"])
    assert is_map(body["state_patch"])
  end

  test "POST /sessions/:id/commands missing name returns 422" do
    {:ok, %{id: id}} = Viber.Server.SessionHandler.create_session(%{})

    conn =
      conn(:post, "/sessions/#{id}/commands", %{"args" => []})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 422
  end

  test "POST /sessions/:id/commands unknown command returns 404" do
    {:ok, %{id: id}} = Viber.Server.SessionHandler.create_session(%{})

    conn =
      conn(:post, "/sessions/#{id}/commands", %{"name" => "no-such", "args" => []})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 404
  end

  test "POST /sessions/:id/commands /model switches model" do
    {:ok, %{id: id}} = Viber.Server.SessionHandler.create_session(%{})

    conn =
      conn(:post, "/sessions/#{id}/commands", %{"name" => "model", "args" => ["haiku"]})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 200
    assert {:ok, body} = Jason.decode(conn.resp_body)
    assert body["state_patch"]["model"] == "haiku"
    assert Enum.any?(body["events"], fn e -> e["type"] == "model_changed" end)
  end

  test "OPTIONS preflight advertises DELETE and last-event-id" do
    conn = conn(:options, "/sessions") |> Router.call(@opts)
    assert conn.status == 200
    assert [methods] = get_resp_header(conn, "access-control-allow-methods")
    assert methods =~ "DELETE"
    assert [headers] = get_resp_header(conn, "access-control-allow-headers")
    assert headers =~ "last-event-id"
  end
end
