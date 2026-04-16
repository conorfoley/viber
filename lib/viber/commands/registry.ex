defmodule Viber.Commands.Registry do
  @moduledoc """
  Registry of slash command specifications with metadata and lookup.
  """

  alias Viber.Commands.Handlers

  @type command_spec :: %{
          name: String.t(),
          aliases: [String.t()],
          description: String.t(),
          usage: String.t(),
          category: :session | :config | :info | :project,
          handler: module()
        }

  @specs [
    %{
      name: "help",
      aliases: [],
      description: "Show available slash commands",
      usage: "/help [command]",
      category: :info,
      handler: Handlers.Help
    },
    %{
      name: "status",
      aliases: [],
      description: "Show current session status",
      usage: "/status",
      category: :info,
      handler: Handlers.Status
    },
    %{
      name: "compact",
      aliases: [],
      description: "Compact conversation history",
      usage: "/compact",
      category: :session,
      handler: Handlers.Compact
    },
    %{
      name: "config",
      aliases: [],
      description: "Show current configuration",
      usage: "/config [key]",
      category: :config,
      handler: Handlers.Config
    },
    %{
      name: "model",
      aliases: [],
      description: "Show or switch the active model",
      usage: "/model [list|model_name]",
      category: :config,
      handler: Handlers.Model
    },
    %{
      name: "clear",
      aliases: [],
      description: "Clear session history",
      usage: "/clear",
      category: :session,
      handler: Handlers.Clear
    },
    %{
      name: "bug",
      aliases: [],
      description: "Generate a bug report template",
      usage: "/bug",
      category: :info,
      handler: Handlers.Bug
    },
    %{
      name: "init",
      aliases: [],
      description: "Initialize project configuration",
      usage: "/init",
      category: :project,
      handler: Handlers.Init
    },
    %{
      name: "attach",
      aliases: [],
      description: "Attach file(s) or glob patterns as context for the LLM",
      usage: "/attach <path|glob> [...]",
      category: :session,
      handler: Handlers.Attach
    },
    %{
      name: "resume",
      aliases: ["sessions"],
      description: "List recent sessions, resume a previous conversation, or purge old sessions",
      usage: "/resume [id|number|purge [days]]",
      category: :session,
      handler: Handlers.Resume
    },
    %{
      name: "reload",
      aliases: [],
      description: "Recompile and hot-reload Viber source modules",
      usage: "/reload",
      category: :project,
      handler: Handlers.Reload
    },
    %{
      name: "connect",
      aliases: [],
      description: "Connect to a database by name or add a new connection from a URL",
      usage: "/connect [name] [url]",
      category: :config,
      handler: Handlers.Connect
    },
    %{
      name: "databases",
      aliases: ["dbs"],
      description: "List configured database connections, test, or remove them",
      usage: "/databases [test <name>|remove <name>]",
      category: :config,
      handler: Handlers.Databases
    },
    %{
      name: "undo",
      aliases: [],
      description: "Remove the last user turn and all subsequent messages from history",
      usage: "/undo",
      category: :session,
      handler: Handlers.Undo
    },
    %{
      name: "retry",
      aliases: [],
      description: "Undo the last turn and re-send the same input",
      usage: "/retry",
      category: :session,
      handler: Handlers.Retry
    },
    %{
      name: "toolset",
      aliases: ["toolsets"],
      description: "Show, enable, or disable tool groups",
      usage: "/toolset [list|enable <name>|disable <name>|reset]",
      category: :config,
      handler: Handlers.Toolset
    },
    %{
      name: "doctor",
      aliases: [],
      description: "Check environment, connectivity, and configuration",
      usage: "/doctor",
      category: :info,
      handler: Handlers.Doctor
    }
  ]

  @by_name Map.new(@specs, fn spec -> {spec.name, spec} end)
  @by_alias Enum.flat_map(@specs, fn spec ->
              Enum.map(spec.aliases, fn a -> {a, spec} end)
            end)
            |> Map.new()
  @lookup Map.merge(@by_alias, @by_name)

  @spec all() :: [command_spec()]
  def all, do: @specs

  @spec get(String.t()) :: {:ok, command_spec()} | :error
  def get(name) do
    case Map.fetch(@lookup, String.downcase(name)) do
      {:ok, _} = result -> result
      :error -> :error
    end
  end

  @names @specs |> Enum.map(& &1.name) |> Enum.sort()

  @spec names() :: [String.t()]
  def names, do: @names
end
