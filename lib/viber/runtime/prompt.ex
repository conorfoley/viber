defmodule Viber.Runtime.Prompt do
  @moduledoc """
  System prompt builder assembling sections into a complete LLM instruction set.
  """

  alias Viber.Runtime.{Bootstrap, Permissions}
  alias Viber.Tools.Registry

  @spec build(keyword()) :: String.t()
  def build(opts \\ []) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    config = Keyword.get(opts, :config)
    permission_mode = Keyword.get(opts, :permission_mode, :prompt)
    custom_instructions = Keyword.get(opts, :custom_instructions)

    [
      role_section(),
      environment_section(project_root),
      tool_instructions_section(),
      tools_section(),
      project_context_section(project_root),
      permission_section(permission_mode),
      config_section(config),
      custom_instructions_section(custom_instructions)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp role_section do
    [
      "You are Viber, an AI coding assistant. You help users with software engineering tasks ",
      "including writing code, debugging, refactoring, and explaining code. ",
      "You have access to tools that let you read files, write files, execute commands, ",
      "search codebases, and fetch web content. Use these tools to accomplish tasks effectively."
    ]
    |> IO.iodata_to_binary()
  end

  defp environment_section(project_root) do
    {os_name, os_version} = detect_os()
    date = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")
    stack = Bootstrap.detect_stack(project_root)

    lines = [
      "# Environment",
      " - Working directory: #{project_root}",
      " - Date: #{date}",
      " - Platform: #{os_name} #{os_version}"
    ]

    lines =
      if stack.language do
        lines ++ [" - Language: #{stack.language}"]
      else
        lines
      end

    lines =
      if stack.framework do
        lines ++ [" - Framework: #{stack.framework}"]
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  defp tool_instructions_section do
    [
      "# Tool Usage Guidelines",
      " - Always read a file before modifying it",
      " - Use the appropriate tool for each task",
      " - Prefer searching (grep/glob) over reading entire directories",
      " - Write minimal, targeted changes when editing files",
      " - Check for errors after making changes"
    ]
    |> Enum.join("\n")
  end

  defp tools_section do
    names = Registry.list_names()

    tool_lines =
      Enum.flat_map(names, fn name ->
        case Registry.get(name) do
          {:ok, spec} -> [" - #{spec.name}: #{spec.description}"]
          :error -> []
        end
      end)

    ["# Available Tools" | tool_lines]
    |> Enum.join("\n")
  end

  defp project_context_section(project_root) do
    candidates = [
      Path.join(project_root, "VIBER.md"),
      Path.join(project_root, "CLAUDE.md"),
      Path.join([project_root, ".viber", "VIBER.md"]),
      Path.join([project_root, ".viber", "instructions.md"])
    ]

    contents =
      Enum.flat_map(candidates, fn path ->
        case File.read(path) do
          {:ok, content} when content != "" ->
            trimmed = String.trim(content)
            if trimmed != "", do: ["## #{Path.basename(path)}\n#{trimmed}"], else: []

          _ ->
            []
        end
      end)

    if contents == [] do
      nil
    else
      ["# Project Instructions" | contents]
      |> Enum.join("\n\n")
    end
  end

  defp permission_section(mode) do
    mode_str = Permissions.mode_to_string(mode)

    [
      "# Permission Mode",
      "Current mode: #{mode_str}",
      permission_description(mode)
    ]
    |> Enum.join("\n")
  end

  defp permission_description(:read_only),
    do: "You can only read files and search. No modifications allowed."

  defp permission_description(:workspace_write),
    do: "You can read and write files in the workspace."

  defp permission_description(:danger_full_access),
    do: "You have full access including shell commands."

  defp permission_description(:allow), do: "All operations are allowed without prompting."

  defp permission_description(:prompt),
    do: "You must ask for permission before modifying files or running commands."

  defp config_section(nil), do: nil

  defp config_section(config) do
    if config.model do
      "# Configuration\n - Model: #{config.model}"
    else
      nil
    end
  end

  defp custom_instructions_section(nil), do: nil
  defp custom_instructions_section(""), do: nil

  defp custom_instructions_section(instructions) do
    "# Custom Instructions\n#{instructions}"
  end

  defp detect_os do
    case :os.type() do
      {:unix, :darwin} -> {"macOS", os_version()}
      {:unix, :linux} -> {"Linux", os_version()}
      {:win32, _} -> {"Windows", os_version()}
      {_, name} -> {to_string(name), ""}
    end
  end

  defp os_version do
    case :os.version() do
      {major, minor, patch} -> "#{major}.#{minor}.#{patch}"
      _ -> ""
    end
  end
end
