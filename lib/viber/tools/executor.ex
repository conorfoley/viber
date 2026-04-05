defmodule Viber.Tools.Executor do
  @moduledoc """
  Dispatches tool execution by name to the appropriate handler.
  """

  alias Viber.Tools.Builtins

  @spec execute(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(name, input) when is_map(input) do
    case Viber.Tools.Registry.normalize_name(name) do
      "bash" -> Builtins.Bash.execute(input)
      "read_file" -> Builtins.FileOps.read(input)
      "write_file" -> Builtins.FileOps.write(input)
      "edit_file" -> Builtins.FileOps.edit(input)
      "grep_search" -> Builtins.Grep.execute(input)
      "glob_search" -> Builtins.Glob.execute(input)
      "ls" -> Builtins.LS.execute(input)
      "web_fetch" -> Builtins.WebFetch.execute(input)
      other -> {:error, "Unknown tool: #{other}"}
    end
  end
end
