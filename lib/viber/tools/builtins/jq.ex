defmodule Viber.Tools.Builtins.Jq do
  @moduledoc """
  Run a jq filter against a JSON file or a JSON string.
  """

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"filter" => filter} = input) do
    cond do
      input["path"] && input["input"] ->
        {:error, "Provide either 'path' or 'input', not both"}

      input["path"] ->
        run(["jq", filter, input["path"]])

      input["input"] ->
        run_with_stdin(["jq", filter], input["input"])

      true ->
        {:error, "Provide either 'path' (a JSON file) or 'input' (a JSON string)"}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: filter"}

  defp run([cmd | args]) do
    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  defp run_with_stdin(cmd_and_args, json_input) do
    tmp = Path.join(System.tmp_dir!(), "viber-jq-#{System.unique_integer([:positive])}.json")
    File.write!(tmp, json_input)

    try do
      run(cmd_and_args ++ [tmp])
    after
      File.rm(tmp)
    end
  end
end
