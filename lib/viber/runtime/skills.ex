defmodule Viber.Runtime.Skills do
  @moduledoc """
  Discovery and loading of project skills.

  Skills are reusable instruction packages stored under
  `.viber/skills/<name>/SKILL.md`. They follow the progressive-disclosure
  pattern: only each skill's name and one-line description are placed in the
  system prompt, and the full instructions are loaded on demand via the
  `skill` tool when a task matches a skill's description.

  A `SKILL.md` may begin with a frontmatter block:

      ---
      name: release-check
      description: Verify a release build before shipping
      ---

      Full instructions follow here...

  When frontmatter is absent, the skill name falls back to the directory
  name and the description to the first non-empty body line.
  """

  @type skill :: %{name: String.t(), description: String.t(), path: String.t()}

  @doc """
  Lists all skills found under `<project_root>/.viber/skills/*/SKILL.md`.
  """
  @spec discover(String.t()) :: [skill()]
  def discover(project_root) do
    project_root
    |> skills_root()
    |> Path.join("*/SKILL.md")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case File.read(path) do
        {:ok, content} -> [build_skill(path, content)]
        {:error, _} -> []
      end
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Loads one skill by name, returning its full instructions and any bundled
  files that live alongside `SKILL.md`.
  """
  @spec load(String.t(), String.t()) ::
          {:ok,
           %{name: String.t(), description: String.t(), content: String.t(), files: [String.t()]}}
          | {:error, String.t()}
  def load(project_root, name) do
    case Enum.find(discover(project_root), fn skill -> skill.name == name end) do
      nil ->
        available =
          case discover(project_root) do
            [] -> "no skills are installed under .viber/skills/"
            skills -> "available: " <> Enum.map_join(skills, ", ", & &1.name)
          end

        {:error, "Unknown skill '#{name}' — #{available}"}

      skill ->
        case File.read(skill.path) do
          {:ok, content} ->
            {_meta, body} = split_frontmatter(content)

            {:ok,
             %{
               name: skill.name,
               description: skill.description,
               content: String.trim(body),
               files: bundled_files(skill.path)
             }}

          {:error, reason} ->
            {:error, "Failed to read #{skill.path}: #{inspect(reason)}"}
        end
    end
  end

  defp skills_root(project_root), do: Path.join([project_root, ".viber", "skills"])

  defp build_skill(path, content) do
    {meta, body} = split_frontmatter(content)
    dir_name = path |> Path.dirname() |> Path.basename()

    %{
      name: Map.get(meta, "name", dir_name),
      description: Map.get(meta, "description", first_line(body)),
      path: path
    }
  end

  defp split_frontmatter("---" <> rest) do
    case String.split(rest, ~r/\n---\s*\n/, parts: 2) do
      [frontmatter, body] -> {parse_frontmatter(frontmatter), body}
      _ -> {%{}, "---" <> rest}
    end
  end

  defp split_frontmatter(content), do: {%{}, content}

  defp parse_frontmatter(frontmatter) do
    frontmatter
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value = String.trim(value)

          if key in ["name", "description"] and value != "" do
            Map.put(acc, key, value)
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  defp first_line(body) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.find("", fn line -> line != "" end)
    |> String.trim_leading("#")
    |> String.trim()
  end

  defp bundled_files(skill_md_path) do
    dir = Path.dirname(skill_md_path)

    dir
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
    |> Enum.reject(&(&1 == "SKILL.md"))
    |> Enum.sort()
  end
end
