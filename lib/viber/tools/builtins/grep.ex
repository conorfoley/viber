defmodule Viber.Tools.Builtins.Grep do
  @moduledoc """
  Grep via ripgrep (rg) system command.
  """

  @default_head_limit 20

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"pattern" => pattern} = input) do
    args = build_args(pattern, input)
    search_path = input["path"] || "."
    offset = input["offset"] || 0

    case System.cmd("rg", args ++ [search_path], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output |> String.trim() |> apply_offset(offset)}
      {output, 1} -> {:ok, "No matches found.\n#{String.trim(output)}"}
      {output, _} -> {:error, "rg error: #{String.trim(output)}"}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: pattern"}

  defp build_args(pattern, input) do
    mode = input["output_mode"] || "files_with_matches"
    head_limit = input["head_limit"] || @default_head_limit
    offset = input["offset"] || 0

    base =
      case mode do
        "files_with_matches" -> ["-l"]
        "count" -> ["-c"]
        _ -> []
      end

    base = base ++ mode_flags(input) ++ [pattern]
    base = if input["glob"], do: base ++ ["--glob", input["glob"]], else: base
    base = if input["type"], do: base ++ ["--type", input["type"]], else: base
    base = if input["-i"], do: base ++ ["-i"], else: base
    base = if input["-n"], do: base ++ ["-n"], else: base
    base = if input["multiline"], do: base ++ ["-U", "--multiline-dotall"], else: base
    base = if input["-B"], do: base ++ ["-B", Integer.to_string(input["-B"])], else: base
    base = if input["-A"], do: base ++ ["-A", Integer.to_string(input["-A"])], else: base
    base = if input["-C"], do: base ++ ["-C", Integer.to_string(input["-C"])], else: base

    if offset > 0 or head_limit do
      base ++ ["--max-count", Integer.to_string(offset + head_limit)]
    else
      base
    end
  end

  defp apply_offset(output, 0), do: output

  defp apply_offset(output, offset) do
    output
    |> String.split("\n")
    |> Enum.drop(offset)
    |> Enum.join("\n")
  end

  defp mode_flags(%{"output_mode" => "content"}), do: []
  defp mode_flags(_), do: []
end
