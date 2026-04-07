defmodule Viber.Tools.Builtins.Formatter do
  @moduledoc """
  Apply `mix format` to a file path or an inline code snippet.
  Supports a `check_only` flag to detect whether formatting is needed without writing.
  """

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(input) do
    path = input["path"]
    content = input["content"]
    check_only = input["check_only"] || false

    cond do
      path && content ->
        {:error, "Provide either 'path' or 'content', not both"}

      path ->
        run_on_path(path, check_only)

      content ->
        run_on_content(content, check_only)

      true ->
        {:error, "Provide either 'path' (a file path) or 'content' (an Elixir code string)"}
    end
  end

  defp run_on_path(path, false) do
    case System.cmd("mix", ["format", path], stderr_to_stdout: true) do
      {_, 0} -> {:ok, "Formatted: #{path}"}
      {output, code} -> {:error, "Exit code: #{code}\n#{String.trim(output)}"}
    end
  end

  defp run_on_path(path, true) do
    case System.cmd("mix", ["format", "--check-formatted", path], stderr_to_stdout: true) do
      {_, 0} -> {:ok, "Already formatted: #{path}"}
      {output, _} -> {:ok, "Not formatted: #{path}\n#{String.trim(output)}"}
    end
  end

  defp run_on_content(content, check_only) do
    tmp =
      Path.join(System.tmp_dir!(), "viber-formatter-#{System.unique_integer([:positive])}.ex")

    File.write!(tmp, content)

    try do
      if check_only do
        case System.cmd("mix", ["format", "--check-formatted", tmp], stderr_to_stdout: true) do
          {_, 0} -> {:ok, "Already formatted."}
          {_, _} -> {:ok, "Not formatted."}
        end
      else
        case System.cmd("mix", ["format", tmp], stderr_to_stdout: true) do
          {_, 0} -> {:ok, File.read!(tmp)}
          {output, code} -> {:error, "Exit code: #{code}\n#{String.trim(output)}"}
        end
      end
    after
      File.rm(tmp)
    end
  end
end
