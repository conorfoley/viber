defmodule Viber.Scheduler.Runner do
  @moduledoc """
  Executes scheduled jobs: runs stored queries/scripts, captures output, triggers alerts.
  """

  require Logger

  alias Viber.Database.ConnectionManager
  alias Viber.Scheduler.{AlertSink, JobStore}

  @query_timeout 60_000

  @spec run(String.t()) :: :ok
  def run(job_id) do
    case JobStore.get_job(job_id) do
      {:ok, job} ->
        Logger.info("Running scheduled job: #{job.name} (#{job.id})")
        execute_job(job)

      {:error, reason} ->
        Logger.warning("Scheduled job #{job_id} not found: #{reason}")
    end

    :ok
  end

  @spec run_now(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def run_now(job_id) do
    case JobStore.get_job(job_id) do
      {:ok, job} ->
        execute_job(job)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_job(job) do
    result =
      case job.type do
        "query" -> run_query(job)
        "script" -> run_script(job)
        "health_check" -> run_health_check(job)
        _ -> {:error, "Unknown job type: #{job.type}"}
      end

    case result do
      {:ok, output} ->
        JobStore.record_run(job.id, "success", output)
        check_alert_rule(job, output)
        {:ok, output}

      {:error, reason} ->
        error_msg = if is_binary(reason), do: reason, else: inspect(reason)
        JobStore.record_run(job.id, "failure", error_msg)
        maybe_alert_on_failure(job, error_msg)
        {:error, error_msg}
    end
  end

  defp run_query(job) do
    query = job.payload["query"] || ""
    db = job.database

    with {:ok, _name, repo} <- resolve_repo(db) do
      try do
        case Ecto.Adapters.SQL.query(repo, query, [], timeout: @query_timeout) do
          {:ok, result} ->
            output = format_query_result(result)
            {:ok, output}

          {:error, %{message: msg}} ->
            {:error, "SQL error: #{msg}"}

          {:error, reason} ->
            {:error, inspect(reason)}
        end
      rescue
        e -> {:error, Exception.message(e)}
      end
    end
  end

  defp run_script(job) do
    script = job.payload["script"] || ""
    timeout = (job.payload["timeout"] || 60) * 1_000

    case System.cmd("sh", ["-c", script],
           stderr_to_stdout: true,
           timeout: timeout
         ) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, "Exit code #{code}: #{output}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp run_health_check(job) do
    query = job.payload["query"] || "SELECT 1"
    db = job.database

    with {:ok, _name, repo} <- resolve_repo(db) do
      start = System.monotonic_time(:millisecond)

      case Ecto.Adapters.SQL.query(repo, query, [], timeout: 10_000) do
        {:ok, _} ->
          elapsed = System.monotonic_time(:millisecond) - start
          {:ok, "Health check OK (#{elapsed}ms)"}

        {:error, %{message: msg}} ->
          {:error, "Health check failed: #{msg}"}

        {:error, reason} ->
          {:error, "Health check failed: #{inspect(reason)}"}
      end
    end
  rescue
    e -> {:error, "Health check failed: #{Exception.message(e)}"}
  end

  defp resolve_repo(nil), do: ConnectionManager.get_active()

  defp resolve_repo(name) do
    case ConnectionManager.get_repo(name) do
      {:ok, repo} -> {:ok, name, repo}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_query_result(result) do
    row_count = result.num_rows
    columns = result.columns || []

    if columns == [] do
      "#{row_count} row(s) affected"
    else
      header = Enum.join(columns, " | ")
      rows = Enum.map(result.rows, fn row -> Enum.map_join(row, " | ", &to_string_safe/1) end)
      Enum.join([header | rows], "\n") <> "\n\n#{row_count} row(s)"
    end
  end

  defp to_string_safe(nil), do: "NULL"
  defp to_string_safe(val) when is_binary(val), do: val
  defp to_string_safe(val), do: inspect(val)

  defp check_alert_rule(%{alert_rule: nil}, _output), do: :ok

  defp check_alert_rule(%{alert_rule: rule, alert_sink: sink} = job, output) when is_map(rule) do
    if alert_triggered?(rule, output) do
      AlertSink.dispatch(job, output, sink)
    end

    :ok
  end

  defp check_alert_rule(_, _), do: :ok

  defp alert_triggered?(%{"condition" => "row_count_gt", "threshold" => threshold}, output) do
    case Regex.run(~r/(\d+) row\(s\)/, output) do
      [_, count_str] -> String.to_integer(count_str) > threshold
      _ -> false
    end
  end

  defp alert_triggered?(%{"condition" => "row_count_eq", "threshold" => threshold}, output) do
    case Regex.run(~r/(\d+) row\(s\)/, output) do
      [_, count_str] -> String.to_integer(count_str) == threshold
      _ -> false
    end
  end

  defp alert_triggered?(%{"condition" => "contains", "pattern" => pattern}, output) do
    String.contains?(output, pattern)
  end

  defp alert_triggered?(_, _), do: false

  defp maybe_alert_on_failure(%{alert_sink: sink} = job, error_msg) when not is_nil(sink) do
    AlertSink.dispatch(job, "JOB FAILED: #{error_msg}", sink)
  end

  defp maybe_alert_on_failure(_, _), do: :ok
end
