defmodule Viber.CLI.Main do
  @moduledoc """
  CLI entry point for Viber — handles arg parsing and boot sequence.
  """

  require Logger

  alias Viber.CLI.{Init, Repl}
  alias Viber.Runtime.{Config, Permissions, Session}
  alias Viber.API.Client
  alias Viber.Tools.MCP.ServerManager

  @spec main([String.t()]) :: no_return()
  def main(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [
          model: :string,
          permission_mode: :string,
          config: :string,
          port: :integer,
          help: :boolean,
          verbose: :boolean
        ],
        aliases: [m: :model, p: :permission_mode, c: :config, h: :help, v: :verbose]
      )

    if opts[:verbose] do
      Logger.configure(level: :debug)
    end

    cond do
      opts[:help] ->
        print_usage()

      match?(["init" | _], rest) ->
        Init.run(File.cwd!())

      true ->
        run_repl(opts)
    end
  end

  defp run_repl(opts) do
    log_path = setup_file_logging()

    config_opts =
      if opts[:config] do
        [project_root: Path.dirname(opts[:config])]
      else
        []
      end

    {:ok, config} = Config.load(config_opts)

    model =
      opts[:model] || config.model || "sonnet"

    resolved_model = Client.resolve_model_alias(model)

    permission_mode =
      if opts[:permission_mode] do
        Permissions.mode_from_string(opts[:permission_mode])
      else
        config.permission_mode || :prompt
      end

    ServerManager.start_servers(config)

    {:ok, session} = Session.start_link()

    IO.puts(welcome_banner(resolved_model, permission_mode, log_path))

    Repl.run(
      session: session,
      model: model,
      config: config,
      permission_mode: permission_mode,
      project_root: File.cwd!()
    )
  end

  defp setup_file_logging do
    log_path = Path.join(System.tmp_dir!(), "viber.log")

    Enum.each(:logger.get_handler_ids(), &:logger.remove_handler/1)

    :logger.add_handler(:viber_file, :logger_std_h, %{
      config: %{file: String.to_charlist(log_path)},
      formatter:
        {:logger_formatter,
         %{
           template: [:time, " [", :level, "] ", :msg, "\n"]
         }}
    })

    log_path
  end

  defp welcome_banner(model, permission_mode, log_path) do
    mode_str = Permissions.mode_to_string(permission_mode)

    """

    #{IO.ANSI.bright()}Viber#{IO.ANSI.reset()} — AI Coding Assistant
    Model: #{model}
    Mode:  #{mode_str}
    Logs:  #{log_path}
    Type /help for commands, or start typing.
    """
  end

  defp print_usage do
    IO.puts("""
    Usage: viber [options] [command]

    Commands:
      init          Initialize project configuration
      (default)     Start interactive REPL

    Options:
      -m, --model MODEL              Set the model (default: sonnet)
      -p, --permission-mode MODE     Set permission mode
      -c, --config PATH              Config file path
      -v, --verbose                  Enable debug logging
      -h, --help                     Show this help
    """)
  end
end
