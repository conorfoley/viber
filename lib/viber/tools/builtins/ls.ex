defmodule Viber.Tools.Builtins.LS do
  @moduledoc """
  Directory listing with tree-style output.
  """

  @default_depth 2

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"path" => path} = input) do
    max_depth = input["depth"] || @default_depth
    ignore = input["ignore"] || []

    if File.dir?(path) do
      tree = build_tree(path, 0, max_depth, ignore)
      {:ok, tree}
    else
      {:error, "Not a directory: #{path}"}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: path"}

  defp build_tree(_dir, depth, max_depth, _ignore) when depth >= max_depth, do: ""

  defp build_tree(dir, depth, max_depth, ignore) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.reject(fn entry -> ignored?(entry, ignore) end)
        |> Enum.map_join("\n", fn entry -> render_entry(dir, entry, depth, max_depth, ignore) end)

      {:error, reason} ->
        "Error listing #{dir}: #{inspect(reason)}"
    end
  end

  defp render_entry(dir, entry, depth, max_depth, ignore) do
    full_path = Path.join(dir, entry)
    prefix = String.duplicate("  ", depth)

    if File.dir?(full_path) do
      subtree = build_tree(full_path, depth + 1, max_depth, ignore)
      "#{prefix}#{entry}/\n#{subtree}"
    else
      "#{prefix}#{entry}"
    end
  end

  defp ignored?(entry, patterns) do
    entry in [".git", ".svn"] or
      Enum.any?(patterns, fn pat ->
        String.contains?(entry, pat) or match_glob?(entry, pat)
      end)
  end

  defp match_glob?(entry, pattern) do
    regex =
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")

    Regex.match?(~r/^#{regex}$/, entry)
  rescue
    _ -> false
  end
end
