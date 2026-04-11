defmodule Viber.Tools.Builtins.Scheduler do
  @moduledoc """
  Tool for managing scheduled cron jobs: create, list, update, delete, enable/disable, run, and view history.
  """

  alias Viber.Scheduler.{JobStore, Runner}

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"action" => "list"}) do
    jobs = JobStore.list_jobs()

    if jobs == [] do
      {:ok, "No scheduled jobs."}
    else
      lines =
        Enum.map(jobs, fn job ->
          status = if job.enabled, do: "enabled", else: "disabled"

          last =
            if job.last_run_at,
              do: Calendar.strftime(job.last_run_at, "%Y-%m-%d %H:%M:%S UTC"),
              else: "never"

          "#{job.id} | #{job.name} | #{job.cron_expr} | #{job.type} | #{status} | last: #{last} (#{job.last_status || "n/a"})"
        end)

      header = "ID | Name | Schedule | Type | Status | Last Run"
      separator = String.duplicate("-", 80)
      {:ok, Enum.join([header, separator | lines], "\n")}
    end
  end

  def execute(%{"action" => "create"} = input) do
    attrs = %{
      name: input["name"],
      cron_expr: input["cron_expr"],
      type: input["type"] || "query",
      payload: input["payload"] || %{},
      database: input["database"],
      alert_rule: input["alert_rule"],
      alert_sink: input["alert_sink"],
      enabled: Map.get(input, "enabled", true)
    }

    case JobStore.create_job(attrs) do
      {:ok, job} ->
        {:ok, "Created job '#{job.name}' (#{job.id}) with schedule '#{job.cron_expr}'"}

      {:error, %Ecto.Changeset{} = cs} ->
        errors = format_changeset_errors(cs)
        {:error, "Failed to create job: #{errors}"}

      {:error, reason} ->
        {:error, "Failed to create job: #{inspect(reason)}"}
    end
  end

  def execute(%{"action" => "update", "id" => id} = input) do
    attrs =
      input
      |> Map.drop(["action", "id"])
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    case JobStore.update_job(id, attrs) do
      {:ok, job} ->
        {:ok, "Updated job '#{job.name}' (#{job.id})"}

      {:error, %Ecto.Changeset{} = cs} ->
        {:error, "Failed to update: #{format_changeset_errors(cs)}"}

      {:error, reason} ->
        {:error, "Failed to update: #{inspect(reason)}"}
    end
  end

  def execute(%{"action" => "delete", "id" => id}) do
    case JobStore.delete_job(id) do
      :ok -> {:ok, "Deleted job #{id}"}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(%{"action" => "enable", "id" => id}) do
    case JobStore.enable_job(id) do
      {:ok, job} -> {:ok, "Enabled job '#{job.name}'"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def execute(%{"action" => "disable", "id" => id}) do
    case JobStore.disable_job(id) do
      {:ok, job} -> {:ok, "Disabled job '#{job.name}'"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def execute(%{"action" => "run_now", "id" => id}) do
    case Runner.run_now(id) do
      {:ok, output} -> {:ok, "Job completed successfully:\n#{output}"}
      {:error, reason} -> {:error, "Job failed: #{reason}"}
    end
  end

  def execute(%{"action" => "history"} = input) do
    job_id = input["id"]
    limit = input["limit"] || 20
    entries = JobStore.history(job_id, limit)

    if entries == [] do
      {:ok, "No run history."}
    else
      lines =
        Enum.map(entries, fn e ->
          ts = Calendar.strftime(e.ran_at, "%Y-%m-%d %H:%M:%S UTC")
          "#{ts} | #{e.job_id} | #{e.status}"
        end)

      header = "Timestamp | Job ID | Status"
      separator = String.duplicate("-", 60)
      {:ok, Enum.join([header, separator | lines], "\n")}
    end
  end

  def execute(%{"action" => action}) do
    {:error, "Unknown scheduler action: #{action}"}
  end

  def execute(_) do
    {:error, "Missing required parameter: action"}
  end

  @spec permission_for(map()) :: :read_only | :danger_full_access
  def permission_for(%{"action" => action}) when action in ~w(list history), do: :read_only
  def permission_for(_), do: :danger_full_access

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
