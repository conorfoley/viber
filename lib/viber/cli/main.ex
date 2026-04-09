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
          version: :boolean,
          verbose: :boolean,
          resume: :string
        ],
        aliases: [
          m: :model,
          p: :permission_mode,
          c: :config,
          h: :help,
          V: :version,
          v: :verbose,
          r: :resume
        ]
      )

    if opts[:verbose] do
      Logger.configure(level: :debug)
    end

    cond do
      opts[:help] ->
        print_usage()

      opts[:version] ->
        IO.puts("viber #{Application.spec(:viber, :vsn)}")

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

    project_root = File.cwd!()

    {:ok, session} =
      if opts[:resume] do
        case Session.resume(opts[:resume]) do
          {:ok, pid} ->
            msg_count = length(Session.get_messages(pid))
            IO.puts("Resumed session #{opts[:resume]} (#{msg_count} messages)")
            {:ok, pid}

          {:error, :not_found} ->
            IO.puts("Session not found: #{opts[:resume]}. Starting new session.")
            Session.start_link(model: model, project_root: project_root)

          {:error, reason} ->
            IO.puts("Failed to resume: #{inspect(reason)}. Starting new session.")
            Session.start_link(model: model, project_root: project_root)
        end
      else
        Session.start_link(model: model, project_root: project_root)
      end

    IO.puts(welcome_banner(resolved_model, permission_mode, log_path))

    Repl.run(
      session: session,
      model: model,
      config: config,
      permission_mode: permission_mode,
      project_root: project_root
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

    mode_color =
      case permission_mode do
        :allow -> :red
        :danger_full_access -> :red
        :workspace_write -> :yellow
        :read_only -> :green
        _ -> :yellow
      end

    content =
      [
        Owl.Data.tag("viber", [:bright, :magenta]),
        Owl.Data.tag(" — AI Coding Assistant", :faint),
        "\n\n",
        Owl.Data.tag("  model ", :faint),
        " ",
        Owl.Data.tag(model, [:bright, :cyan]),
        "\n",
        Owl.Data.tag("  mode  ", :faint),
        " ",
        Owl.Data.tag(mode_str, [:bright, mode_color]),
        "\n",
        Owl.Data.tag("  logs  ", :faint),
        " ",
        Owl.Data.tag(log_path, :faint),
        "\n\n",
        Owl.Data.tag("  Type ", :faint),
        Owl.Data.tag("/help", :cyan),
        Owl.Data.tag(" for commands, or start typing.", :faint)
      ]

    banner =
      content
      |> Owl.Box.new(
        padding_x: 1,
        border_style: :solid_rounded,
        border_tag: :light_black
      )
      |> Owl.Data.to_chardata()

    ["\n", banner, "\n"]
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
      -r, --resume SESSION_ID        Resume a previous session
      -v, --verbose                  Enable debug logging
      -V, --version                  Show version
      -h, --help                     Show this help
    """)
  end
end
