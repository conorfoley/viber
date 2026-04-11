defmodule Viber.Tools.Builtins.MysqlQuery do
  @moduledoc """
  Execute SQL queries against a managed database connection with safety guardrails.
  """

  alias Viber.Database.ConnectionManager

  @default_timeout 30_000
  @default_limit 100
  @max_output_bytes 200_000

  @read_only_prefixes ~w(SELECT SHOW DESCRIBE EXPLAIN WITH)
  @write_prefixes ~w(INSERT UPDATE DELETE REPLACE)
  @ddl_prefixes ~w(DROP ALTER TRUNCATE CREATE RENAME)

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"query" => query} = input) do
    format = input["format"] || "table"
    timeout = normalize_timeout(input["timeout"])

    with {:ok, conn_name, repo} <- resolve_repo_with_name(input["database"]),
         :ok <- check_read_only(conn_name, query),
         {:ok, safe_query} <- apply_safety(query, input) do
      run_query(repo, safe_query, format, timeout)
    end
  end

  def execute(_), do: {:error, "Missing required parameter: query"}

  @spec permission_for(map()) :: :read_only | :workspace_write | :danger_full_access
  def permission_for(%{"query" => query}) when is_binary(query) do
    classify_query(query)
  end

  def permission_for(_), do: :danger_full_access

  defp classify_query(query) do
    normalized = query |> String.trim() |> String.upcase()

    cond do
      contains_keyword?(normalized, @ddl_prefixes) -> :danger_full_access
      contains_keyword?(normalized, @write_prefixes) -> :workspace_write
      starts_with_any?(normalized, @read_only_prefixes) -> :read_only
      true -> :danger_full_access
    end
  end

  defp contains_keyword?(sql, keywords) do
    Enum.any?(keywords, fn kw ->
      Regex.match?(~r/\b#{kw}\b/, sql)
    end)
  end

  defp starts_with_any?(str, prefixes) do
    Enum.any?(prefixes, &String.starts_with?(str, &1))
  end

  defp resolve_repo_with_name(nil) do
    ConnectionManager.get_active()
  end

  defp resolve_repo_with_name(name) do
    case ConnectionManager.get_repo(name) do
      {:ok, repo} -> {:ok, name, repo}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_read_only(conn_name, query) do
    if ConnectionManager.is_read_only?(conn_name) && classify_query(query) != :read_only do
      {:error,
       "Connection '#{conn_name}' is read-only; only SELECT/SHOW/DESCRIBE/EXPLAIN queries are allowed"}
    else
      :ok
    end
  end

  defp apply_safety(query, input) do
    normalized = query |> String.trim() |> String.upcase()

    cond do
      starts_with_any?(normalized, @ddl_prefixes) ->
        {:ok, query}

      starts_with_any?(normalized, @write_prefixes) && !has_where?(normalized) &&
          input["force"] != true ->
        {:error,
         "Refusing #{hd(String.split(normalized))} without WHERE clause. Add a WHERE clause or pass \"force\": true to override."}

      starts_with_any?(normalized, @read_only_prefixes) && !has_limit?(normalized) ->
        limit = input["limit"] || @default_limit
        {:ok, String.trim_trailing(query, ";") <> " LIMIT #{limit}"}

      true ->
        {:ok, query}
    end
  end

  defp has_where?(normalized), do: normalized =~ ~r/\bWHERE\b/
  defp has_limit?(normalized), do: normalized =~ ~r/\bLIMIT\b/

  defp run_query(repo, query, format, timeout) do
    start = System.monotonic_time(:millisecond)

    try do
      case Ecto.Adapters.SQL.query(repo, query, [], timeout: timeout) do
        {:ok, result} ->
          elapsed = System.monotonic_time(:millisecond) - start
          output = format_result(result, format, elapsed)
          {:ok, truncate_output(output)}

        {:error, %{message: message}} ->
          {:error, "SQL error: #{message}"}

        {:error, reason} ->
          {:error, "Query failed: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "Query error: #{Exception.message(e)}"}
    end
  end

  defp format_result(result, "json", elapsed) do
    rows =
      Enum.map(result.rows, fn row ->
        result.columns
        |> Enum.zip(row)
        |> Map.new()
      end)

    meta = %{
      row_count: result.num_rows,
      execution_time_ms: elapsed,
      columns: result.columns
    }

    Jason.encode!(%{meta: meta, rows: rows}, pretty: true)
  end

  defp format_result(result, "csv", elapsed) do
    header = Enum.join(result.columns, ",")

    rows =
      Enum.map(result.rows, fn row ->
        Enum.map_join(row, ",", &csv_escape/1)
      end)

    body = Enum.join([header | rows], "\n")
    "#{body}\n\n-- #{result.num_rows} row(s), #{elapsed}ms"
  end

  defp format_result(result, _table, elapsed) do
    if result.columns == nil || result.columns == [] do
      "Query OK, #{result.num_rows} row(s) affected (#{elapsed}ms)"
    else
      col_widths = compute_col_widths(result.columns, result.rows)
      separator = Enum.map_join(col_widths, "-+-", &String.duplicate("-", &1))
      header = format_row(result.columns, col_widths)

      body =
        Enum.map(result.rows, fn row ->
          row
          |> Enum.map(&to_display_string/1)
          |> format_row(col_widths)
        end)

      lines = [header, separator | body]
      table = Enum.join(lines, "\n")
      "#{table}\n\n#{result.num_rows} row(s) (#{elapsed}ms)"
    end
  end

  defp compute_col_widths(columns, rows) do
    initial = Enum.map(columns, &String.length/1)

    Enum.reduce(rows, initial, fn row, widths ->
      row
      |> Enum.map(fn val -> val |> to_display_string() |> String.length() end)
      |> Enum.zip(widths)
      |> Enum.map(fn {a, b} -> max(a, b) end)
    end)
    |> Enum.map(&min(&1, 60))
  end

  defp format_row(values, widths) do
    values
    |> Enum.zip(widths)
    |> Enum.map_join(" | ", fn {val, width} ->
      val
      |> to_display_string()
      |> String.slice(0, width)
      |> String.pad_trailing(width)
    end)
  end

  defp to_display_string(nil), do: "NULL"
  defp to_display_string(val) when is_binary(val), do: val
  defp to_display_string(val), do: inspect(val)

  defp csv_escape(nil), do: ""

  defp csv_escape(val) do
    str = to_display_string(val)

    if String.contains?(str, [",", "\"", "\n"]) do
      "\"" <> String.replace(str, "\"", "\"\"") <> "\""
    else
      str
    end
  end

  defp truncate_output(output) when byte_size(output) > @max_output_bytes do
    binary_part(output, 0, @max_output_bytes) <> "\n... (output truncated at 200KB)"
  end

  defp truncate_output(output), do: output

  defp normalize_timeout(nil), do: @default_timeout
  defp normalize_timeout(val) when is_integer(val), do: val * 1_000
  defp normalize_timeout(_), do: @default_timeout
end
