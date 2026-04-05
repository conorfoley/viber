defmodule Viber.Tools.MCP.ProtocolTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.MCP.Protocol

  test "encode_request produces valid JSON-RPC with id" do
    result = Protocol.encode_request(1, "initialize", %{"key" => "value"})
    {:ok, decoded} = Jason.decode(String.trim(result))
    assert decoded["jsonrpc"] == "2.0"
    assert decoded["id"] == 1
    assert decoded["method"] == "initialize"
    assert decoded["params"] == %{"key" => "value"}
  end

  test "encode_request without params omits params field" do
    result = Protocol.encode_request(2, "tools/list")
    {:ok, decoded} = Jason.decode(String.trim(result))
    refute Map.has_key?(decoded, "params")
    assert decoded["id"] == 2
  end

  test "encode_notification has no id field" do
    result = Protocol.encode_notification("notifications/initialized")
    {:ok, decoded} = Jason.decode(String.trim(result))
    assert decoded["jsonrpc"] == "2.0"
    assert decoded["method"] == "notifications/initialized"
    refute Map.has_key?(decoded, "id")
  end

  test "decode_message handles success response" do
    json = Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{"ok" => true}})
    assert {:ok, msg} = Protocol.decode_message(json)
    assert msg.type == :response
    assert msg.id == 1
    assert msg.result == %{"ok" => true}
  end

  test "decode_message handles error response" do
    json =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "error" => %{"code" => -32600, "message" => "Invalid request"}
      })

    assert {:ok, msg} = Protocol.decode_message(json)
    assert msg.type == :error_response
    assert msg.error["code"] == -32600
  end

  test "decode_message handles notification" do
    json = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "update", "params" => %{}})
    assert {:ok, msg} = Protocol.decode_message(json)
    assert msg.type == :notification
    assert msg.method == "update"
  end

  test "decode_message rejects non-jsonrpc" do
    assert {:error, :invalid_jsonrpc} = Protocol.decode_message(~s({"id": 1}))
  end

  test "messages are newline-terminated" do
    assert String.ends_with?(Protocol.encode_request(1, "test"), "\n")
    assert String.ends_with?(Protocol.encode_notification("test"), "\n")
  end
end
