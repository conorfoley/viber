defmodule Viber.Tools.Builtins.DataExport do
  @moduledoc """
  Export query results to files in CSV, JSON, or SQL INSERT format.
  """

  alias Viber.Database.ConnectionManager

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"query" => query, "path" => path, "format" => format} = input) do
    with {:ok, repo} <- resolve_repo(input["database"]),
         {:ok, result} <- run_query(repo, query),
         :ok <- write_export(result, path, format, input["table_name"]) do
      {:ok, "Exported #{result.num_rows} row(s) to #{path} (#{format})"}
    end
  end

  def execute(%{"query" => _, "path" => _} = input) do
    execute(Map.put(input, "format", "csv"))
  end

  def execute(_) do
    {:error,
     "Missing required parameters: query, path. Optional: format (csv|json|sql), database, table_name (for sql format)"}
  end

  defp resolve_repo(nil) do
    case ConnectionManager.get_active() do
      {:ok, _name, repo} -> {:ok, repo}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_repo(name), do: ConnectionManager.get_repo(name)

  defp run_query(repo, query) do
    case Ecto.Adapters.SQL.query(repo, query, [], timeout: 120_000) do
      {:ok, result} -> {:ok, result}
      {:error, %{message: msg}} -> {:error, "Query failed: #{msg}"}
      {:error, reason} -> {:error, "Query failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Query error: #{Exception.message(e)}"}
  end

  defp write_export(result, path, "csv", _table_name) do
    header = Enum.join(result.columns, ",")

    rows =
      Enum.map(result.rows, fn row ->
        Enum.map_join(row, ",", &csv_escape/1)
      end)

    content = Enum.join([header | rows], "\n") <> "\n"
    File.write(path, content)
  end

  defp write_export(result, path, "json", _table_name) do
    rows =
      Enum.map(result.rows, fn row ->
        result.columns
        |> Enum.zip(row)
        |> Map.new(fn {col, val} -> {col, normalize_json_value(val)} end)
      end)

    content = Jason.encode!(rows, pretty: true)
    File.write(path, content <> "\n")
  end

  defp write_export(result, path, "sql", table_name) do
    table = table_name || "exported_table"
    cols = Enum.join(result.columns, ", ")

    statements =
      Enum.map(result.rows, fn row ->
        values = Enum.map_join(row, ", ", &sql_escape/1)
        "INSERT INTO #{table} (#{cols}) VALUES (#{values});"
      end)

    content = Enum.join(statements, "\n") <> "\n"
    File.write(path, content)
  end

  defp write_export(_result, _path, format, _table_name) do
    {:error, "Unknown export format: #{format}. Supported: csv, json, sql"}
  end

  defp csv_escape(nil), do: ""

  defp csv_escape(val) do
    str = to_string_safe(val)

    if String.contains?(str, [",", "\"", "\n"]) do
      "\"" <> String.replace(str, "\"", "\"\"") <> "\""
    else
      str
    end
  end

  defp sql_escape(nil), do: "NULL"
  defp sql_escape(val) when is_integer(val), do: Integer.to_string(val)
  defp sql_escape(val) when is_float(val), do: Float.to_string(val)
  defp sql_escape(val) when is_boolean(val), do: if(val, do: "TRUE", else: "FALSE")

  defp sql_escape(val) do
    escaped = val |> to_string_safe() |> String.replace("'", "''")
    "'#{escaped}'"
  end

  defp normalize_json_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp normalize_json_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp normalize_json_value(%Date{} = d), do: Date.to_iso8601(d)
  defp normalize_json_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp normalize_json_value(val), do: val

  defp to_string_safe(nil), do: ""
  defp to_string_safe(val) when is_binary(val), do: val
  defp to_string_safe(val), do: inspect(val)
end
