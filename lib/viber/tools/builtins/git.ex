defmodule Viber.Tools.Builtins.Git do
  @moduledoc """
  Git operations within the current workspace.
  """

  @default_timeout 60_000
  @max_output_bytes 100_000

  @read_only_subcommands ~w(status log diff show reflog shortlog describe rev-parse ls-files ls-tree blame)

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"subcommand" => subcommand} = input) do
    args = build_args(subcommand, input)
    timeout_ms = normalize_timeout(input["timeout"])
    start = System.monotonic_time(:millisecond)

    task =
      Task.async(fn ->
        System.cmd("git", args, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, exit_code}} ->
        elapsed = System.monotonic_time(:millisecond) - start
        truncated = truncate_output(output)
        {:ok, format_result(exit_code, truncated, elapsed)}

      nil ->
        elapsed = System.monotonic_time(:millisecond) - start
        {:ok, "Exit code: timeout\nExecution time: #{elapsed}ms\nGit command exceeded timeout"}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: subcommand"}

  @spec read_only?(String.t()) :: boolean()
  def read_only?(subcommand), do: subcommand in @read_only_subcommands

  @spec permission_for(map()) :: :read_only | :workspace_write
  def permission_for(%{"subcommand" => sub}) when is_binary(sub) do
    if read_only?(sub), do: :read_only, else: :workspace_write
  end

  def permission_for(_), do: :workspace_write

  defp build_args(subcommand, input) do
    extra = input["args"] || []
    [subcommand | extra]
  end

  defp truncate_output(output) when byte_size(output) > @max_output_bytes do
    binary_part(output, 0, @max_output_bytes) <> "\n... (output truncated at 100KB)"
  end

  defp truncate_output(output), do: output

  defp format_result(exit_code, output, elapsed) do
    "Exit code: #{exit_code}\nExecution time: #{elapsed}ms\n#{output}"
  end

  defp normalize_timeout(nil), do: @default_timeout
  defp normalize_timeout(val) when is_integer(val), do: val * 1_000
  defp normalize_timeout(_), do: @default_timeout
end
