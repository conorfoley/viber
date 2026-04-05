defmodule Viber.Tools.Builtins.Glob do
  @moduledoc """
  File glob search via Path.wildcard/2.
  """

  @default_head_limit 40

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"pattern" => pattern} = input) do
    head_limit = input["head_limit"] || @default_head_limit
    base_path = input["path"] || "."
    full_pattern = Path.join(base_path, pattern)

    results =
      full_pattern
      |> Path.wildcard(match_dot: false)
      |> sort_by_mtime()
      |> Enum.take(head_limit)

    {:ok, "Found #{length(results)} results\n#{Enum.join(results, "\n")}"}
  end

  def execute(_), do: {:error, "Missing required parameter: pattern"}

  defp sort_by_mtime(paths) do
    Enum.sort_by(
      paths,
      fn path ->
        case File.stat(path) do
          {:ok, %{mtime: mtime}} -> mtime
          _ -> {{1970, 1, 1}, {0, 0, 0}}
        end
      end,
      :desc
    )
  end
end
