defmodule Viber.Tools.MCP.Protocol do
  @moduledoc """
  JSON-RPC 2.0 message encoding and decoding for MCP.
  """

  @spec encode_request(integer(), String.t(), map() | nil) :: binary()
  def encode_request(id, method, params \\ nil) do
    msg = %{"jsonrpc" => "2.0", "id" => id, "method" => method}
    msg = if params, do: Map.put(msg, "params", params), else: msg
    Jason.encode!(msg) <> "\n"
  end

  @spec encode_notification(String.t(), map() | nil) :: binary()
  def encode_notification(method, params \\ nil) do
    msg = %{"jsonrpc" => "2.0", "method" => method}
    msg = if params, do: Map.put(msg, "params", params), else: msg
    Jason.encode!(msg) <> "\n"
  end

  @spec decode_message(binary()) :: {:ok, map()} | {:error, term()}
  def decode_message(data) do
    case Jason.decode(data) do
      {:ok, %{"jsonrpc" => "2.0"} = msg} -> {:ok, classify(msg)}
      {:ok, _} -> {:error, :invalid_jsonrpc}
      {:error, _} = err -> err
    end
  end

  defp classify(%{"id" => id, "result" => result} = msg) do
    %{type: :response, id: id, result: result, error: nil, raw: msg}
  end

  defp classify(%{"id" => id, "error" => error} = msg) do
    %{type: :error_response, id: id, result: nil, error: error, raw: msg}
  end

  defp classify(%{"id" => id, "method" => method} = msg) do
    %{type: :request, id: id, method: method, params: msg["params"], raw: msg}
  end

  defp classify(%{"method" => method} = msg) do
    %{type: :notification, method: method, params: msg["params"], raw: msg}
  end

  defp classify(msg) do
    %{type: :unknown, raw: msg}
  end

  @spec initialize_params() :: map()
  def initialize_params do
    %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{},
      "clientInfo" => %{
        "name" => "viber",
        "version" => to_string(Application.spec(:viber, :vsn) || "0.1.0")
      }
    }
  end

  @spec tool_call_params(String.t(), map()) :: map()
  def tool_call_params(name, arguments) do
    %{"name" => name, "arguments" => arguments}
  end
end
