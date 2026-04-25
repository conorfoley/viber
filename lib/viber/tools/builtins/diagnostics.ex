defmodule Viber.Tools.Builtins.Diagnostics do
  @moduledoc """
  Run static analysis tools (Dialyzer or Credo) and return structured findings.
  """

  @default_timeout 300_000

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"tool" => tool} = input) when tool in ["dialyzer", "credo"] do
    path = input["path"]

    task_ref =
      Task.async(fn ->
        System.cmd("mix", build_args(tool, path), stderr_to_stdout: true)
      end)

    case Task.yield(task_ref, @default_timeout) || Task.shutdown(task_ref, :brutal_kill) do
      {:ok, {output, _exit_code}} ->
        if tool_unavailable?(output) do
          {:ok,
           "Tool: #{tool}\nError: #{tool} is not available in this project. Make sure it is listed as a dependency."}
        else
          findings = parse_output(tool, output)
          filtered = filter_by_path(findings, path)
          {:ok, format_findings(tool, filtered, output)}
        end

      nil ->
        {:ok, "Tool: #{tool}\nError: Analysis exceeded timeout"}
    end
  end

  def execute(%{"tool" => tool}) do
    {:error, "Unknown tool: #{tool}. Supported tools: dialyzer, credo"}
  end

  def execute(_), do: {:error, "Missing required parameter: tool"}

  defp build_args("dialyzer", _path), do: ["dialyzer", "--format", "dialyxir"]
  defp build_args("credo", nil), do: ["credo", "--format", "oneline"]
  defp build_args("credo", path), do: ["credo", "--format", "oneline", path]

  defp tool_unavailable?(output) do
    output =~ "could not find task" or
      output =~ "is not available" or
      output =~ "Mix.NoTaskError"
  end

  defp parse_output("dialyzer", output) do
    output
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/(.+\.exs?):(\d+):(.*)/, String.trim(line)) do
        [_, file, line_num, message] -> [{:dialyzer, file, line_num, String.trim(message)}]
        _ -> []
      end
    end)
  end

  defp parse_output("credo", output) do
    output
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/\[([CDFR])\] ›\s+(.+):(\d+):\d+\s+(.*)/, line) do
        [_, severity, file, line_num, message] ->
          [{:credo, severity, file, line_num, String.trim(message)}]

        _ ->
          []
      end
    end)
  end

  defp filter_by_path(findings, nil), do: findings

  defp filter_by_path(findings, path) do
    abs_path = Path.expand(path)

    Enum.filter(findings, fn
      {:dialyzer, file, _, _} ->
        abs_file = Path.expand(file)
        String.starts_with?(abs_file, abs_path)

      {:credo, _, file, _, _} ->
        abs_file = Path.expand(file)
        String.starts_with?(abs_file, abs_path)
    end)
  end

  defp format_findings("dialyzer", findings, raw_output) do
    count = length(findings)

    body =
      if count == 0 do
        "No warnings found."
      else
        Enum.map_join(findings, "\n", fn {:dialyzer, file, line, message} ->
          "#{file}:#{line}: #{message}"
        end)
      end

    "Tool: dialyzer\nFindings: #{count}\n\n#{body}\n\n--- Raw Output ---\n#{raw_output}"
  end

  defp format_findings("credo", findings, raw_output) do
    count = length(findings)

    body =
      if count == 0 do
        "No issues found."
      else
        Enum.map_join(findings, "\n", fn {:credo, severity, file, line, message} ->
          "[#{severity}] #{file}:#{line}: #{message}"
        end)
      end

    "Tool: credo\nFindings: #{count}\n\n#{body}\n\n--- Raw Output ---\n#{raw_output}"
  end
end
