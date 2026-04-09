defmodule Viber.Application do
  @moduledoc """
  OTP Application for Viber.
  """

  use Application

  @impl true
  def start(_type, _args) do
    Viber.Tools.Registry.init_mcp_table()

    children =
      repo_children() ++
        [
          {Registry, keys: :unique, name: Viber.SessionRegistry},
          {DynamicSupervisor, name: Viber.SessionSupervisor, strategy: :one_for_one},
          {Task.Supervisor, name: Viber.TaskSupervisor},
          {Registry, keys: :unique, name: Viber.MCPRegistry},
          Viber.Tools.MCP.ServerManager
        ] ++ server_children() ++ hot_reload_children()

    opts = [strategy: :one_for_one, name: Viber.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp repo_children do
    if Application.get_env(:viber, :enable_repo, true) do
      [Viber.Repo]
    else
      []
    end
  end

  defp hot_reload_children do
    if Application.get_env(:viber, :hot_reload, false) do
      [{Viber.HotReloader, project_root: File.cwd!()}]
    else
      []
    end
  end

  defp server_children do
    if Application.get_env(:viber, :start_server, false) do
      port = Application.get_env(:viber, :server_port, 4100)
      [{Bandit, plug: Viber.Server.Router, port: port}]
    else
      []
    end
  end
end
