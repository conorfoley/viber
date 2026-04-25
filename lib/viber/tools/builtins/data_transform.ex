defmodule Viber.Tools.Builtins.DataTransform do
  @moduledoc """
  In-memory transformations on query result sets: group, sort, filter, pivot, sample.
  """

  alias Viber.Database.ConnectionManager

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"query" => query, "transform" => transform} = input) do
    with {:ok, repo} <- resolve_repo(input["database"]),
         {:ok, result} <- run_query(repo, query) do
      rows = to_maps(result.columns, result.rows)
      apply_transform(transform, rows, input)
    end
  end

  def execute(_) do
    {:error, "Required: query, transform (group|sort|filter|pivot|sample|select|rename)"}
  end

  defp resolve_repo(nil) do
    case ConnectionManager.get_active() do
      {:ok, _name, repo} -> {:ok, repo}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_repo(name), do: ConnectionManager.get_repo(name)

  defp run_query(repo, query) do
    case Ecto.Adapters.SQL.query(repo, query, [], timeout: 60_000) do
      {:ok, result} -> {:ok, result}
      {:error, %{message: msg}} -> {:error, "Query failed: #{msg}"}
      {:error, reason} -> {:error, "Query failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Query error: #{Exception.message(e)}"}
  end

  defp to_maps(columns, rows) do
    Enum.map(rows, fn row ->
      columns |> Enum.zip(row) |> Map.new()
    end)
  end

  defp apply_transform("group", rows, %{"group_by" => group_col} = input) do
    agg_col = input["agg_column"]
    agg_fn = input["agg_function"] || "count"

    grouped = Enum.group_by(rows, &Map.get(&1, group_col))

    result =
      Enum.map(grouped, fn {key, group_rows} ->
        agg_value = compute_aggregate(group_rows, agg_col, agg_fn)
        %{group_col => key, "#{agg_fn}(#{agg_col || "*"})" => agg_value}
      end)
      |> Enum.sort_by(&Map.get(&1, group_col))

    {:ok, format_maps(result)}
  end

  defp apply_transform("sort", rows, %{"sort_by" => col} = input) do
    direction = input["direction"] || "asc"

    sorted =
      case direction do
        "desc" -> Enum.sort_by(rows, &Map.get(&1, col), :desc)
        _ -> Enum.sort_by(rows, &Map.get(&1, col))
      end

    {:ok, format_maps(sorted)}
  end

  defp apply_transform("filter", rows, %{
         "filter_column" => col,
         "filter_op" => op,
         "filter_value" => val
       }) do
    filtered = Enum.filter(rows, fn row -> compare(Map.get(row, col), op, val) end)
    {:ok, format_maps(filtered) <> "\n\n#{length(filtered)} of #{length(rows)} row(s) matched"}
  end

  defp apply_transform("sample", rows, input) do
    n = input["count"] || 10
    sampled = Enum.take_random(rows, min(n, length(rows)))
    {:ok, format_maps(sampled) <> "\n\nSampled #{length(sampled)} of #{length(rows)} row(s)"}
  end

  defp apply_transform("select", rows, %{"columns" => cols}) when is_list(cols) do
    projected = Enum.map(rows, fn row -> Map.take(row, cols) end)
    {:ok, format_maps(projected)}
  end

  defp apply_transform("rename", rows, %{"renames" => renames}) when is_map(renames) do
    renamed =
      Enum.map(rows, fn row ->
        Enum.reduce(renames, row, fn {old, new}, acc ->
          case Map.pop(acc, old) do
            {nil, acc} -> acc
            {val, acc} -> Map.put(acc, new, val)
          end
        end)
      end)

    {:ok, format_maps(renamed)}
  end

  defp apply_transform(
         "pivot",
         rows,
         %{"pivot_column" => pivot_col, "value_column" => value_col} = input
       ) do
    group_col = input["group_column"]

    if group_col do
      pivot_values = rows |> Enum.map(&Map.get(&1, pivot_col)) |> Enum.uniq() |> Enum.sort()

      pivoted =
        rows
        |> Enum.group_by(&Map.get(&1, group_col))
        |> Enum.map(fn {key, group_rows} ->
          base = %{group_col => key}

          Enum.reduce(group_rows, base, fn row, acc ->
            pv = to_display(Map.get(row, pivot_col))
            Map.put(acc, pv, Map.get(row, value_col))
          end)
        end)
        |> Enum.sort_by(&Map.get(&1, group_col))

      all_cols = [group_col | Enum.map(pivot_values, &to_display/1)]
      {:ok, format_maps_ordered(pivoted, all_cols)}
    else
      {:error, "pivot requires group_column, pivot_column, and value_column"}
    end
  end

  defp apply_transform(transform, _rows, _input) do
    {:error,
     "Unknown transform: #{transform}. Supported: group, sort, filter, sample, select, rename, pivot"}
  end

  defp compute_aggregate(rows, _col, "count"), do: length(rows)

  defp compute_aggregate(rows, col, "sum") do
    rows |> Enum.map(&to_number(Map.get(&1, col))) |> Enum.sum()
  end

  defp compute_aggregate(rows, col, "avg") do
    vals = Enum.map(rows, &to_number(Map.get(&1, col)))

    if vals == [] do
      0
    else
      Float.round(Enum.sum(vals) / length(vals), 2)
    end
  end

  defp compute_aggregate(rows, col, "min") do
    rows |> Enum.map(&Map.get(&1, col)) |> Enum.min(fn -> nil end)
  end

  defp compute_aggregate(rows, col, "max") do
    rows |> Enum.map(&Map.get(&1, col)) |> Enum.max(fn -> nil end)
  end

  defp compute_aggregate(_rows, _col, fn_name), do: {:error, "Unknown aggregate: #{fn_name}"}

  defp compare(val, "=", target), do: to_display(val) == target
  defp compare(val, "!=", target), do: to_display(val) != target
  defp compare(val, ">", target), do: to_number(val) > to_number(target)
  defp compare(val, "<", target), do: to_number(val) < to_number(target)
  defp compare(val, ">=", target), do: to_number(val) >= to_number(target)
  defp compare(val, "<=", target), do: to_number(val) <= to_number(target)
  defp compare(val, "contains", target), do: String.contains?(to_display(val), target)
  defp compare(_val, _op, _target), do: false

  defp to_number(val) when is_integer(val), do: val
  defp to_number(val) when is_float(val), do: val

  defp to_number(val) when is_binary(val) do
    case Float.parse(val) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_number(_), do: 0

  defp to_display(nil), do: "NULL"
  defp to_display(val) when is_binary(val), do: val
  defp to_display(val), do: inspect(val)

  defp format_maps([]), do: "(empty result)"

  defp format_maps(rows) do
    columns = rows |> hd() |> Map.keys() |> Enum.sort()
    format_maps_ordered(rows, columns)
  end

  defp format_maps_ordered(rows, columns) do
    col_widths =
      Enum.map(columns, fn col ->
        max_val =
          rows
          |> Enum.map(&(&1 |> Map.get(col) |> to_display() |> String.length()))
          |> Enum.max(fn -> 0 end)

        max(String.length(to_display(col)), max_val) |> min(60)
      end)

    header = format_row(columns, col_widths)
    separator = Enum.map_join(col_widths, "-+-", &String.duplicate("-", &1))

    body =
      Enum.map(rows, fn row ->
        vals = Enum.map(columns, &to_display(Map.get(row, &1)))
        format_row(vals, col_widths)
      end)

    Enum.join([header, separator | body], "\n")
  end

  defp format_row(values, widths) do
    values
    |> Enum.zip(widths)
    |> Enum.map_join(" | ", fn {val, w} ->
      val |> to_display() |> String.slice(0, w) |> String.pad_trailing(w)
    end)
  end
end
