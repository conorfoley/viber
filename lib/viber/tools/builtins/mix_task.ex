defmodule Viber.Tools.Builtins.MixTask do
  @moduledoc """
  Run an arbitrary Mix task with optional args and timeout.
  """

  @default_timeout 120_000
  @max_output_bytes 100_000

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"task" => task} = input) do
    args = input["args"] || []
    timeout_ms = normalize_timeout(input["timeout"])
    start = System.monotonic_time(:millisecond)

    task_ref =
      Task.async(fn ->
        System.cmd("mix", [task | args], stderr_to_stdout: true)
      end)

    case Task.yield(task_ref, timeout_ms) || Task.shutdown(task_ref, :brutal_kill) do
      {:ok, {output, exit_code}} ->
        elapsed = System.monotonic_time(:millisecond) - start
        truncated = truncate_output(output)
        {:ok, format_result(exit_code, truncated, elapsed)}

      nil ->
        elapsed = System.monotonic_time(:millisecond) - start
        {:ok, format_result(:timeout, "", elapsed)}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: task"}

  defp truncate_output(output) when byte_size(output) > @max_output_bytes do
    binary_part(output, 0, @max_output_bytes) <> "\n... (output truncated at 100KB)"
  end

  defp truncate_output(output), do: output

  defp format_result(:timeout, _output, elapsed) do
    "Exit code: timeout\nExecution time: #{elapsed}ms\nTask exceeded timeout"
  end

  defp format_result(exit_code, output, elapsed) do
    "Exit code: #{exit_code}\nExecution time: #{elapsed}ms\n#{output}"
  end

  defp normalize_timeout(nil), do: @default_timeout
  defp normalize_timeout(val) when is_integer(val), do: val * 1_000
  defp normalize_timeout(_), do: @default_timeout
end
