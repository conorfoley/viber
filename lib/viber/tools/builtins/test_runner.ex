defmodule Viber.Tools.Builtins.TestRunner do
  @moduledoc """
  Run `mix test` with optional path/line targeting and parse ExUnit output into a structured summary.
  """

  @default_timeout 120_000
  @max_output_bytes 100_000

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(input) when is_map(input) do
    args = build_args(input)
    timeout_ms = input["timeout"] || @default_timeout
    start = System.monotonic_time(:millisecond)

    task_ref =
      Task.async(fn ->
        System.cmd("mix", ["test" | args], stderr_to_stdout: true)
      end)

    case Task.yield(task_ref, timeout_ms) || Task.shutdown(task_ref, :brutal_kill) do
      {:ok, {output, exit_code}} ->
        elapsed = System.monotonic_time(:millisecond) - start
        truncated = truncate_output(output)
        {:ok, format_result(exit_code, truncated, elapsed)}

      nil ->
        elapsed = System.monotonic_time(:millisecond) - start
        {:ok, "Status: error\nExecution time: #{elapsed}ms\nTest run exceeded timeout"}
    end
  end

  defp build_args(input) do
    base =
      case input["path"] do
        nil ->
          []

        path ->
          case input["line"] do
            nil -> [path]
            line -> ["#{path}:#{line}"]
          end
      end

    extra = input["args"] || []
    base ++ extra
  end

  defp truncate_output(output) when byte_size(output) > @max_output_bytes do
    binary_part(output, 0, @max_output_bytes) <> "\n... (output truncated at 100KB)"
  end

  defp truncate_output(output), do: output

  defp format_result(exit_code, output, elapsed) do
    status = status_from_exit_code(exit_code)
    summary = parse_summary(output)
    failures = parse_failures(output)

    header =
      [
        "Status: #{status}",
        summary,
        "Execution time: #{elapsed}ms"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    failures_section =
      if failures != "" do
        "\n--- Failures ---\n#{failures}"
      else
        ""
      end

    "#{header}#{failures_section}\n\n--- Raw Output ---\n#{output}"
  end

  defp status_from_exit_code(0), do: "passed"
  defp status_from_exit_code(1), do: "failed"
  defp status_from_exit_code(_), do: "error"

  defp parse_summary(output) do
    case Regex.run(~r/(\d+) tests?, (\d+) failures?(?:, (\d+) skipped)?/, output) do
      [_, tests, failures | rest] ->
        skipped = List.first(rest)

        parts = ["Tests: #{tests}", "Failures: #{failures}"]
        parts = if skipped, do: parts ++ ["Skipped: #{skipped}"], else: parts
        Enum.join(parts, "  ")

      nil ->
        nil
    end
  end

  defp parse_failures(output) do
    case Regex.run(~r/\n(\s+1\) .+?)(?:\n\nFinished|\nRandomized|\z)/s, output) do
      nil ->
        ""

      [_, block] ->
        block
        |> String.trim()
        |> then(fn trimmed ->
          if trimmed == "", do: "", else: trimmed
        end)
    end
  end
end
