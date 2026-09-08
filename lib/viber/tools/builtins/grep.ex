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
    head_limit = input["head_limit"] || @default_head_limit

    case System.cmd("rg", args ++ [search_path], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output |> String.trim() |> paginate(offset, head_limit)}
      {output, 1} -> {:ok, "No matches found.\n#{String.trim(output)}"}
      {output, _} -> {:error, "rg error: #{String.trim(output)}"}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: pattern"}

  defp build_args(pattern, input) do
    mode = input["output_mode"] || "files_with_matches"

    mode_arg(mode)
    |> Kernel.++(mode_flags(input))
    |> Kernel.++([pattern])
    |> append_flag(input["glob"], &["--glob", &1])
    |> append_flag(input["type"], &["--type", &1])
    |> append_flag(input["-i"], fn _ -> ["-i"] end)
    |> append_flag(input["-n"], fn _ -> ["-n"] end)
    |> append_flag(input["multiline"], fn _ -> ["-U", "--multiline-dotall"] end)
    |> append_flag(input["-B"], &["-B", Integer.to_string(&1)])
    |> append_flag(input["-A"], &["-A", Integer.to_string(&1)])
    |> append_flag(input["-C"], &["-C", Integer.to_string(&1)])
    |> append_max_count(mode, input)
  end

  defp mode_arg("files_with_matches"), do: ["-l"]
  defp mode_arg("count"), do: ["-c"]
  defp mode_arg(_mode), do: []

  defp append_flag(base, nil, _to_args), do: base
  defp append_flag(base, false, _to_args), do: base
  defp append_flag(base, value, to_args), do: base ++ to_args.(value)

  defp append_max_count(base, "content", input) do
    head_limit = input["head_limit"] || @default_head_limit
    offset = input["offset"] || 0
    base ++ ["--max-count", Integer.to_string(offset + head_limit)]
  end

  defp append_max_count(base, _mode, _input), do: base

  defp paginate(output, offset, head_limit) do
    output
    |> String.split("\n")
    |> Enum.drop(offset)
    |> Enum.take(head_limit)
    |> Enum.join("\n")
  end

  defp mode_flags(%{"output_mode" => "content"}), do: []
  defp mode_flags(_), do: []
end
