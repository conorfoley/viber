defmodule Viber.Tools.Builtins.Skill do
  @moduledoc """
  Loads the full instructions of a project skill on demand.

  Skills are listed by name and description in the system prompt; this tool
  performs the second step of progressive disclosure by returning the full
  `SKILL.md` body (and the paths of any bundled files) for one skill.
  """

  alias Viber.Runtime.Skills

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"name" => name} = input) when is_binary(name) do
    project_root = project_root(input)

    case Skills.load(project_root, name) do
      {:ok, skill} -> {:ok, format(skill)}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(_input), do: {:error, "skill: 'name' is required"}

  defp project_root(input) do
    case Map.get(input, "project_root") do
      root when is_binary(root) and root != "" -> root
      _ -> File.cwd!()
    end
  end

  defp format(skill) do
    header = "# Skill: #{skill.name}\n#{skill.description}"

    files_section =
      case skill.files do
        [] ->
          nil

        files ->
          "## Bundled files (relative to the skill directory)\n" <>
            Enum.map_join(files, "\n", &(" - " <> &1))
      end

    [header, skill.content, files_section]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end
end
