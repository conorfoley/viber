defmodule Viber.Tools.Toolsets do
  @moduledoc """
  Named toolset definitions grouping built-in tools by domain.

  Toolsets allow enabling or disabling groups of tools in one step.
  The `:core` toolset is always available regardless of configuration.
  """

  @type toolset_info :: %{
          name: atom(),
          label: String.t(),
          description: String.t(),
          tools: [String.t()]
        }

  @toolsets [
    %{
      name: :core,
      label: "Core",
      description: "File system, search, and shell tools (always enabled)",
      tools:
        ~w[bash read_file write_file edit_file multi_edit glob_search grep_search ls spawn_agent]
    },
    %{
      name: :web,
      label: "Web",
      description: "HTTP fetching and web browsing tools",
      tools: ~w[web_fetch]
    },
    %{
      name: :coding,
      label: "Coding",
      description: "Testing, diagnostics, formatting, git, and mix tools",
      tools: ~w[test_runner diagnostics formatter mix_task git]
    },
    %{
      name: :database,
      label: "Database",
      description: "SQL queries, schema inspection, and data export tools",
      tools:
        ~w[ecto_schema_inspector mysql_query mysql_schema mysql_explain data_export data_transform]
    },
    %{
      name: :scheduling,
      label: "Scheduling",
      description: "Cron job management and automation tools",
      tools: ~w[scheduler]
    },
    %{
      name: :system,
      label: "System",
      description: "Clipboard, JSON processing, and user interaction tools",
      tools: ~w[clipboard jq user_input]
    }
  ]

  @all_names Enum.map(@toolsets, & &1.name)

  @spec all() :: [toolset_info()]
  def all, do: @toolsets

  @spec all_names() :: [atom()]
  def all_names, do: @all_names

  @spec get(atom()) :: toolset_info() | nil
  def get(name) do
    Enum.find(@toolsets, fn ts -> ts.name == name end)
  end

  @spec parse(String.t()) :: {:ok, atom()} | {:error, String.t()}
  def parse(name) do
    atom = String.to_existing_atom(name)

    if atom in @all_names do
      {:ok, atom}
    else
      {:error, "Unknown toolset: #{name}. Available: #{Enum.join(@all_names, ", ")}"}
    end
  rescue
    ArgumentError ->
      {:error, "Unknown toolset: #{name}. Available: #{Enum.join(@all_names, ", ")}"}
  end
end
