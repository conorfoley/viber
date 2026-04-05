defmodule Viber.Tools.Builtins.Bash do
  @moduledoc """
  Bash command execution with timeout and output capture.
  """

  @default_timeout 240_000
  @max_output_bytes 100_000

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"command" => command} = input) do
    timeout_ms = input["timeout"] || @default_timeout
    start = System.monotonic_time(:millisecond)

    task =
      Task.async(fn ->
        System.cmd("bash", ["-c", command], stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, exit_code}} ->
        elapsed = System.monotonic_time(:millisecond) - start
        truncated = truncate_output(output)
        {:ok, format_result(exit_code, truncated, elapsed)}

      nil ->
        elapsed = System.monotonic_time(:millisecond) - start
        {:ok, format_result(:timeout, "", elapsed)}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: command"}

  defp truncate_output(output) when byte_size(output) > @max_output_bytes do
    binary_part(output, 0, @max_output_bytes) <> "\n... (output truncated at 100KB)"
  end

  defp truncate_output(output), do: output

  defp format_result(:timeout, _output, elapsed) do
    "Exit code: timeout\nExecution time: #{elapsed}ms\nCommand exceeded timeout"
  end

  defp format_result(exit_code, output, elapsed) do
    "Exit code: #{exit_code}\nExecution time: #{elapsed}ms\n#{output}"
  end
end
