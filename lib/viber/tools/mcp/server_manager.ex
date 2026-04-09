defmodule Viber.Tools.MCP.ServerManager do
  @moduledoc """
  DynamicSupervisor managing MCP server processes.
  """

  use DynamicSupervisor

  alias Viber.Tools.MCP.{Client, Server}
  alias Viber.Tools.Spec

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def terminate(_reason, _state) do
    for {name, _pid} <- list_servers() do
      stop_server(name)
    end

    :ok
  end

  @spec start_servers(Viber.Runtime.Config.t()) :: {:ok, non_neg_integer()}
  def start_servers(config) do
    started =
      config.mcp_servers
      |> Enum.map(fn {name, server_config} -> start_server(name, server_config) end)
      |> Enum.count(fn result -> match?({:ok, _}, result) end)

    {:ok, started}
  end

  @spec start_server(String.t(), Viber.Runtime.Config.mcp_server_config()) ::
          {:ok, pid()} | {:error, term()}
  def start_server(name, {:stdio, %{command: command, args: args, env: env}}) do
    opts = [server_name: name, command: command, args: args, env: env]

    case DynamicSupervisor.start_child(__MODULE__, {Server, opts}) do
      {:ok, pid} ->
        discover_tools(pid, name)
        {:ok, pid}

      {:error, _} = err ->
        err
    end
  end

  def start_server(_name, _config) do
    {:error, :unsupported_transport}
  end

  @spec stop_server(String.t()) :: :ok | {:error, term()}
  def stop_server(name) do
    case Registry.lookup(Viber.MCPRegistry, name) do
      [{pid, _}] ->
        Viber.Tools.Registry.unregister_mcp_tools(name)
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @spec list_servers() :: [{String.t(), pid()}]
  def list_servers do
    Registry.select(Viber.MCPRegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @spec get_all_tools() :: [Spec.t()]
  def get_all_tools do
    list_servers()
    |> Enum.flat_map(fn {name, pid} ->
      tools = Server.get_tools(pid)
      Enum.map(tools, fn tool -> mcp_tool_to_spec(name, tool) end)
    end)
  end

  defp discover_tools(pid, server_name) do
    case Client.initialize(pid) do
      {:ok, _} ->
        Server.request(pid, "notifications/initialized", %{})

        case Client.list_tools(pid) do
          {:ok, tools} ->
            Server.set_tools(pid, tools)
            specs = Enum.map(tools, fn tool -> mcp_tool_to_spec(server_name, tool) end)
            Viber.Tools.Registry.register_mcp_tools(server_name, specs)
            {:ok, length(tools)}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  defp mcp_tool_to_spec(server_name, tool) do
    normalized_server = Viber.Tools.Registry.normalize_name(server_name)
    normalized_tool = Viber.Tools.Registry.normalize_name(tool["name"] || "")
    original_tool_name = tool["name"] || ""
    captured_server_name = server_name

    handler = fn input ->
      call_mcp_tool(captured_server_name, original_tool_name, input)
    end

    %Spec{
      name: "mcp__#{normalized_server}__#{normalized_tool}",
      description: tool["description"] || "",
      input_schema: tool["inputSchema"] || %{"type" => "object", "properties" => %{}},
      permission: :workspace_write,
      handler: handler
    }
  end

  defp call_mcp_tool(server_name, tool_name, input) do
    case Registry.lookup(Viber.MCPRegistry, server_name) do
      [{pid, _}] ->
        Client.call_tool(pid, tool_name, input)

      [] ->
        {:error, "MCP server '#{server_name}' is not running"}
    end
  end
end
