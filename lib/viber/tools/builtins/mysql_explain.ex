defmodule Viber.Tools.Builtins.MysqlExplain do
  @moduledoc """
  Run EXPLAIN or EXPLAIN ANALYZE on a query and return the execution plan.
  """

  alias Viber.Database.ConnectionManager

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"query" => query} = input) do
    with {:ok, repo} <- resolve_repo(input["database"]) do
      analyze = input["analyze"] != false
      run_explain(repo, query, analyze)
    end
  end

  def execute(_), do: {:error, "Missing required parameter: query"}

  defp resolve_repo(nil) do
    case ConnectionManager.get_active() do
      {:ok, _name, repo} -> {:ok, repo}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_repo(name), do: ConnectionManager.get_repo(name)

  defp run_explain(repo, query, analyze) do
    prefix = if analyze, do: "EXPLAIN ANALYZE ", else: "EXPLAIN "
    explain_query = prefix <> String.trim(query)

    case Ecto.Adapters.SQL.query(repo, explain_query, [], timeout: 60_000) do
      {:ok, result} ->
        output = format_explain(result)
        {:ok, output}

      {:error, %{message: message}} ->
        {:error, "EXPLAIN failed: #{message}"}

      {:error, reason} ->
        {:error, "EXPLAIN failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "EXPLAIN error: #{Exception.message(e)}"}
  end

  defp format_explain(result) do
    if result.columns && length(result.columns) > 0 do
      header = Enum.join(result.columns, " | ")

      rows =
        Enum.map(result.rows, fn row ->
          Enum.map_join(row, " | ", &to_string_safe/1)
        end)

      Enum.join([header, String.duplicate("-", String.length(header)) | rows], "\n")
    else
      Enum.map_join(result.rows, "\n", fn row ->
        Enum.map_join(row, " ", &to_string_safe/1)
      end)
    end
  end

  defp to_string_safe(nil), do: "NULL"
  defp to_string_safe(val) when is_binary(val), do: val
  defp to_string_safe(val), do: inspect(val)
end
