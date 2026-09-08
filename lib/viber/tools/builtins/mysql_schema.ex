defmodule Viber.Tools.Builtins.MysqlSchema do
  @moduledoc """
  Database schema introspection for MySQL and PostgreSQL connections.
  """

  alias Viber.Database.ConnectionManager

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"action" => action} = input) do
    with {:ok, repo} <- resolve_repo(input["database"]) do
      run_action(action, input, repo)
    end
  end

  def execute(_), do: {:error, "Missing required parameter: action"}

  defp resolve_repo(nil) do
    case ConnectionManager.get_active() do
      {:ok, _name, repo} -> {:ok, repo}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_repo(name), do: ConnectionManager.get_repo(name)

  defp run_action("list_databases", _input, repo) do
    case query(repo, "SHOW DATABASES") do
      {:ok, result} ->
        {:ok, format_db_list(result)}

      {:error, _} ->
        list_databases_postgres(repo)
    end
  end

  defp run_action("list_tables", input, repo) do
    filter = input["filter"]

    case query(repo, "SHOW TABLES") do
      {:ok, result} ->
        tables = result.rows |> Enum.map(fn [t | _] -> t end) |> filter_tables(filter)
        {:ok, format_table_list(tables)}

      {:error, _} ->
        list_tables_postgres(repo, filter)
    end
  end

  defp run_action("describe_table", %{"table" => table}, repo) do
    with {:ok, columns} <- describe_columns(repo, table),
         {:ok, indexes} <- describe_indexes(repo, table),
         {:ok, row_count} <- estimate_row_count(repo, table) do
      output = [
        "Table: #{table}",
        "Estimated rows: #{row_count}",
        "",
        "Columns:",
        columns,
        "",
        "Indexes:",
        indexes
      ]

      {:ok, Enum.join(output, "\n")}
    end
  end

  defp run_action("describe_table", _input, _repo) do
    {:error, "Missing required parameter: table"}
  end

  defp run_action("show_create", %{"table" => table}, repo) do
    case query(repo, "SHOW CREATE TABLE `#{sanitize_identifier(table)}`") do
      {:ok, %{rows: [[_, create_sql | _]]}} ->
        {:ok, create_sql}

      {:error, _} ->
        sql = """
        SELECT
          'CREATE TABLE ' || tablename || ' (' ||
          string_agg(column_name || ' ' || data_type || coalesce('(' || character_maximum_length::text || ')', ''), ', ')
          || ')'
        FROM information_schema.columns
        WHERE table_name = $1 AND table_schema = 'public'
        GROUP BY tablename
        """

        case Ecto.Adapters.SQL.query(repo, sql, [table]) do
          {:ok, %{rows: [[create]]}} -> {:ok, create}
          {:error, reason} -> {:error, "Failed: #{inspect(reason)}"}
        end
    end
  end

  defp run_action("show_create", _input, _repo) do
    {:error, "Missing required parameter: table"}
  end

  defp run_action("relationships", input, repo) do
    table = input["table"]

    {sql, params} =
      if table do
        safe_table = sanitize_identifier(table)

        {"""
         SELECT
           TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
         FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
         WHERE REFERENCED_TABLE_NAME IS NOT NULL
           AND (TABLE_NAME = '#{safe_table}' OR REFERENCED_TABLE_NAME = '#{safe_table}')
         """, []}
      else
        {"""
         SELECT
           TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
         FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
         WHERE REFERENCED_TABLE_NAME IS NOT NULL
         ORDER BY TABLE_NAME
         """, []}
      end

    case query_params(repo, sql, params) do
      {:ok, result} -> {:ok, format_relationships(result.rows)}
      {:error, reason} -> {:error, "Failed to query relationships: #{inspect(reason)}"}
    end
  end

  defp run_action("search_columns", %{"pattern" => pattern}, repo) do
    like = "%" <> pattern <> "%"

    case search_columns_query(repo, like) do
      {:ok, %{rows: []}} -> {:ok, "No columns matching '#{pattern}'."}
      {:ok, %{rows: rows}} -> {:ok, format_column_matches(rows)}
      {:error, reason} -> {:error, "Failed to search columns: #{inspect(reason)}"}
    end
  end

  defp run_action("search_columns", _input, _repo) do
    {:error, "Missing required parameter: pattern"}
  end

  defp run_action(action, _input, _repo) do
    {:error,
     "Unknown action: #{action}. Valid actions: list_databases, list_tables, describe_table, show_create, relationships, search_columns"}
  end

  defp describe_columns(repo, table) do
    case query(repo, "DESCRIBE `#{sanitize_identifier(table)}`") do
      {:ok, result} -> {:ok, format_mysql_columns(result.rows)}
      {:error, _} -> describe_columns_postgres(repo, table)
    end
  end

  defp describe_columns_postgres(repo, table) do
    sql = """
    SELECT column_name, data_type, is_nullable, column_default
    FROM information_schema.columns
    WHERE table_name = $1 AND table_schema = 'public'
    ORDER BY ordinal_position
    """

    case query_params(repo, sql, [table]) do
      {:ok, result} -> {:ok, format_postgres_columns(result.rows)}
      {:error, reason} -> {:error, "Failed to describe table: #{inspect(reason)}"}
    end
  end

  defp format_mysql_columns(rows) do
    Enum.map_join(rows, "\n", fn row ->
      [field, type, null, key, default, extra] =
        Enum.take(row, 6) ++ List.duplicate(nil, max(0, 6 - length(row)))

      key_str = if key && key != "", do: " [#{key}]", else: ""
      null_str = if null == "YES", do: " NULL", else: " NOT NULL"
      default_str = if default, do: " DEFAULT #{default}", else: ""
      extra_str = if extra && extra != "", do: " #{extra}", else: ""
      "  #{field}  #{type}#{null_str}#{default_str}#{key_str}#{extra_str}"
    end)
  end

  defp format_postgres_columns(rows) do
    Enum.map_join(rows, "\n", fn [col, dtype, nullable, default] ->
      null_str = if nullable == "YES", do: " NULL", else: " NOT NULL"
      default_str = if default, do: " DEFAULT #{default}", else: ""
      "  #{col}  #{dtype}#{null_str}#{default_str}"
    end)
  end

  defp describe_indexes(repo, table) do
    case query(repo, "SHOW INDEX FROM `#{sanitize_identifier(table)}`") do
      {:ok, result} -> {:ok, format_mysql_indexes(result.rows)}
      {:error, _} -> describe_indexes_postgres(repo, table)
    end
  end

  defp describe_indexes_postgres(repo, table) do
    sql = """
    SELECT indexname, indexdef
    FROM pg_indexes
    WHERE tablename = $1
    """

    case query_params(repo, sql, [table]) do
      {:ok, result} -> {:ok, format_postgres_indexes(result.rows)}
      {:error, reason} -> {:error, "Failed to get indexes: #{inspect(reason)}"}
    end
  end

  defp format_mysql_indexes(rows) do
    rows
    |> Enum.group_by(fn row -> Enum.at(row, 2) end)
    |> Enum.map_join("\n", fn {name, rows} ->
      unique = if Enum.at(hd(rows), 1) == 0, do: "UNIQUE ", else: ""
      cols = Enum.map_join(rows, ", ", fn row -> Enum.at(row, 4) end)
      "  #{unique}#{name} (#{cols})"
    end)
  end

  defp format_postgres_indexes(rows) do
    Enum.map_join(rows, "\n", fn [name, defn] -> "  #{name}: #{defn}" end)
  end

  defp estimate_row_count(repo, table) do
    case query(repo, "SELECT COUNT(*) FROM `#{sanitize_identifier(table)}`") do
      {:ok, %{rows: [[count]]}} ->
        {:ok, count}

      {:error, _} ->
        case query_params(
               repo,
               "SELECT reltuples::bigint FROM pg_class WHERE relname = $1",
               [table]
             ) do
          {:ok, %{rows: [[count]]}} -> {:ok, count}
          _ -> {:ok, "unknown"}
        end
    end
  end

  defp list_databases_postgres(repo) do
    case query(
           repo,
           "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname"
         ) do
      {:ok, result} -> {:ok, format_db_list(result)}
      {:error, reason} -> {:error, "Failed to list databases: #{inspect(reason)}"}
    end
  end

  defp format_db_list(result) do
    dbs = Enum.map(result.rows, fn [db] -> db end)
    "Databases:\n" <> Enum.map_join(dbs, "\n", &"  #{&1}")
  end

  defp list_tables_postgres(repo, filter) do
    sql = "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename"

    case query(repo, sql) do
      {:ok, result} ->
        tables = result.rows |> Enum.map(fn [t] -> t end) |> filter_tables(filter)
        {:ok, format_table_list(tables)}

      {:error, reason} ->
        {:error, "Failed to list tables: #{inspect(reason)}"}
    end
  end

  defp filter_tables(tables, nil), do: tables

  defp filter_tables(tables, filter) do
    Enum.filter(tables, &String.contains?(&1, filter))
  end

  defp format_table_list(tables) do
    "Tables (#{length(tables)}):\n" <> Enum.map_join(tables, "\n", &"  #{&1}")
  end

  defp format_relationships([]), do: "No foreign key relationships found."

  defp format_relationships(rows) do
    lines =
      Enum.map(rows, fn [tbl, col, ref_tbl, ref_col] ->
        "  #{tbl}.#{col} → #{ref_tbl}.#{ref_col}"
      end)

    "Foreign Key Relationships:\n" <> Enum.join(lines, "\n")
  end

  defp search_columns_query(repo, like) do
    case query_params(repo, "SHOW DATABASES", []) do
      {:ok, _} ->
        sql = """
        SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE COLUMN_NAME LIKE ? OR DATA_TYPE LIKE ?
        ORDER BY TABLE_NAME, ORDINAL_POSITION
        """

        query_params(repo, sql, [like, like])

      {:error, _} ->
        sql = """
        SELECT table_name, column_name, data_type, is_nullable, column_default
        FROM information_schema.columns
        WHERE column_name ILIKE $1 OR data_type ILIKE $2
        ORDER BY table_name, ordinal_position
        """

        query_params(repo, sql, [like, like])
    end
  end

  defp format_column_matches(rows) do
    lines =
      Enum.map(rows, fn [tbl, col, dtype, nullable, default] ->
        null_str = if nullable == "YES", do: " NULL", else: " NOT NULL"
        default_str = if default, do: " DEFAULT #{default}", else: ""
        "  #{tbl}.#{col}  #{dtype}#{null_str}#{default_str}"
      end)

    "Matching columns (#{length(lines)}):\n" <> Enum.join(lines, "\n")
  end

  defp query(repo, sql) do
    query_params(repo, sql, [])
  end

  defp query_params(repo, sql, params) do
    case Ecto.Adapters.SQL.query(repo, sql, params, timeout: 15_000) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp sanitize_identifier(name) do
    String.replace(name, ~r/[^a-zA-Z0-9_.]/, "")
  end
end
