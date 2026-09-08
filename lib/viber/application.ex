defmodule Viber.Application do
  @moduledoc """
  OTP Application for Viber.
  """

  use Application

  @impl true
  def start(_type, _args) do
    maybe_add_file_logger()
    Viber.Tools.Registry.init_mcp_table()

    children =
      repo_children() ++
        [
          Viber.Database.ConnectionManager,
          Viber.Runtime.Permissions.Broker,
          Viber.Runtime.BrowserAction.Broker,
          Viber.Server.Interrupts,
          {Registry, keys: :unique, name: Viber.SessionRegistry},
          {DynamicSupervisor, name: Viber.SessionSupervisor, strategy: :one_for_one},
          {Task.Supervisor, name: Viber.TaskSupervisor},
          {Registry, keys: :unique, name: Viber.MCPRegistry},
          Viber.Tools.MCP.ServerManager
        ] ++
        scheduler_children() ++ gateway_children() ++ server_children() ++ hot_reload_children()

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

  defp scheduler_children do
    if Application.get_env(:viber, :enable_scheduler, true) do
      [Viber.Scheduler, Viber.Scheduler.JobStore]
    else
      []
    end
  end

  defp gateway_children do
    if Application.get_env(:viber, :enable_gateway, true) do
      [Viber.Gateway.Router]
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

  defp maybe_add_file_logger do
    if Mix.env() == :dev do
      :logger.update_handler_config(:default, :level, :warning)

      log_path = Path.join(File.cwd!(), "log/server.log")
      File.mkdir_p!(Path.dirname(log_path))

      :logger.add_handler(:file_logger, :logger_std_h, %{
        config: %{
          type: :file,
          file: String.to_charlist(log_path),
          filesync_repeat_interval: 1000
        },
        level: :info,
        formatter:
          {:logger_formatter,
           %{
             template: [:time, " [", :level, "] ", :msg, "\n"],
             single_line: true
           }}
      })
    end
  rescue
    e ->
      IO.puts("[Application] Failed to set up file logger: #{inspect(e)}")
  end
end
