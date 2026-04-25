defmodule Viber.Scheduler.AlertSink do
  @moduledoc """
  Dispatches alerts from scheduled job runs to configured sinks (Slack webhook, file, log).
  """

  require Logger

  @spec dispatch(map(), String.t(), map() | nil) :: :ok
  def dispatch(_job, _output, nil), do: :ok

  def dispatch(job, output, sink) when is_map(sink) do
    sink_type = sink["type"] || "log"

    case sink_type do
      "slack" -> send_slack(job, output, sink)
      "file" -> write_file(job, output, sink)
      "log" -> write_log(job, output)
      _ -> Logger.warning("Unknown alert sink type: #{sink_type}")
    end

    :ok
  end

  defp send_slack(job, output, sink) do
    url = sink["webhook_url"]

    if url do
      payload =
        Jason.encode!(%{
          text: "🔔 *Viber Job Alert: #{job.name}*\n```#{String.slice(output, 0, 2000)}```"
        })

      case Req.post(url, body: payload, headers: [{"content-type", "application/json"}]) do
        {:ok, %{status: status}} when status in 200..299 ->
          Logger.info("Slack alert sent for job #{job.name}")

        {:ok, %{status: status}} ->
          Logger.warning("Slack alert failed for job #{job.name}: HTTP #{status}")

        {:error, reason} ->
          Logger.warning("Slack alert failed for job #{job.name}: #{inspect(reason)}")
      end
    else
      Logger.warning("Slack alert sink missing webhook_url for job #{job.name}")
    end
  end

  defp write_file(job, output, sink) do
    path = sink["path"] || "viber_alerts.log"
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    line = "[#{timestamp}] [#{job.name}] #{output}\n"

    case File.write(path, line, [:append]) do
      :ok ->
        Logger.info("Alert written to #{path} for job #{job.name}")

      {:error, reason} ->
        Logger.warning("Failed to write alert file #{path}: #{inspect(reason)}")
    end
  end

  defp write_log(job, output) do
    Logger.info("Job alert [#{job.name}]: #{String.slice(output, 0, 500)}")
  end
end
