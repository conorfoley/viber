defmodule Viber.Tools.MCP.Client do
  @moduledoc """
  High-level MCP client operations over a Server GenServer.

  `call_tool/3` classifies failures with `Viber.Tools.Failure`: a server that
  is not running is `:not_sent`; a timeout or a server that exits mid-call is
  `:unknown` because the tool may already have run.
  """

  alias Viber.Runtime.Errors
  alias Viber.Tools.Failure
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

  @spec call_tool(pid(), String.t(), map()) :: {:ok, String.t()} | {:error, Failure.t()}
  def call_tool(server, name, arguments) do
    params = Protocol.tool_call_params(name, arguments)

    case Server.request(server, "tools/call", params) do
      {:ok, %{"isError" => true} = result} ->
        text = content_text(result["content"])
        message = if text == "", do: "MCP tool returned an error", else: text
        {:error, Failure.new(:error, message, {:mcp_tool_error, result})}

      {:ok, %{"content" => content}} ->
        {:ok, content_text(content)}

      {:ok, result} ->
        {:ok, inspect(result)}

      {:error, reason} ->
        {:error, classify_error(name, reason)}
    end
  end

  defp classify_error(name, :not_running),
    do: Failure.new(:not_sent, "MCP server for '#{name}' is not running", :not_running)

  defp classify_error(name, :timeout),
    do: Failure.new(:unknown, "MCP tool '#{name}' timed out", :timeout)

  defp classify_error(name, :server_exited),
    do: Failure.new(:unknown, "MCP server exited while running '#{name}'", :server_exited)

  defp classify_error(name, {:exit, _} = reason),
    do: Failure.new(:unknown, "MCP tool '#{name}' failed: #{Errors.message(reason)}", reason)

  defp classify_error(name, reason),
    do: Failure.new(:error, "MCP tool '#{name}' failed: #{Errors.message(reason)}", reason)

  defp content_text(content) when is_list(content) do
    content
    |> Enum.filter(fn c -> c["type"] == "text" end)
    |> Enum.map_join("\n", fn c -> c["text"] end)
  end

  defp content_text(_), do: ""
end
