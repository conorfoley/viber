defmodule Viber.Tools.MCP.Client do
  @moduledoc """
  High-level MCP client operations over a Server GenServer.
  """

  alias Viber.Tools.MCP.{Protocol, Server}

  @spec initialize(pid()) :: {:ok, map()} | {:error, term()}
  def initialize(server) do
    Server.request(server, "initialize", Protocol.initialize_params())
  end

  @spec list_tools(pid()) :: {:ok, [map()]} | {:error, term()}
  def list_tools(server) do
    case Server.request(server, "tools/list", %{}) do
      {:ok, %{"tools" => tools}} -> {:ok, tools}
      {:ok, result} -> {:ok, result["tools"] || []}
      {:error, _} = err -> err
    end
  end

  @spec call_tool(pid(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def call_tool(server, name, arguments) do
    params = Protocol.tool_call_params(name, arguments)

    case Server.request(server, "tools/call", params) do
      {:ok, %{"content" => content}} ->
        text =
          content
          |> Enum.filter(fn c -> c["type"] == "text" end)
          |> Enum.map_join("\n", fn c -> c["text"] end)

        {:ok, text}

      {:ok, %{"isError" => true} = result} ->
        {:error, inspect(result)}

      {:ok, result} ->
        {:ok, inspect(result)}

      {:error, _} = err ->
        err
    end
  end
end
