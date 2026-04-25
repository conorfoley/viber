defmodule Viber.Commands.Handlers.Resume do
  @moduledoc """
  Handler for the /resume command. Lists recent sessions or resumes a specific one.
  """

  use Viber.Commands.Handler

  alias Viber.Runtime.{Session, SessionStore}

  @spec execute([String.t()], map()) ::
          {:ok, String.t()} | {:error, String.t()} | {:resume, pid()}
  def execute([], _context) do
    sessions = SessionStore.list_recent(10)

    if sessions == [] do
      {:ok, "No previous sessions found."}
    else
      lines =
        sessions
        |> Enum.with_index(1)
        |> Enum.map(fn {s, idx} ->
          title = s.title || "(untitled)"
          title = String.slice(title, 0, 60)
          model = s.model || "?"
          ago = format_ago(s.updated_at)
          "  #{idx}. [#{s.id}] #{title}  (#{model}, #{ago})"
        end)

      header = "Recent sessions:\n"
      footer = "\n\nUsage: /resume <id or number>"

      {:ok, header <> Enum.join(lines, "\n") <> footer}
    end
  end

  def execute(["list" | _], context) do
    execute([], context)
  end

  def execute(["purge"], _context) do
    count = SessionStore.delete_older_than(30)
    {:ok, "Purged #{count} session(s) older than 30 days."}
  end

  def execute(["purge", days_str | _], _context) do
    case Integer.parse(days_str) do
      {days, ""} when days > 0 ->
        count = SessionStore.delete_older_than(days)
        {:ok, "Purged #{count} session(s) older than #{days} day(s)."}

      _ ->
        {:error, "Invalid number of days: #{days_str}"}
    end
  end

  def execute([selector | _], _context) do
    session_id = resolve_selector(selector)

    case Session.resume(session_id) do
      {:ok, pid} ->
        {:resume, pid}

      {:error, :not_found} ->
        {:error, "Session '#{selector}' not found."}

      {:error, reason} ->
        {:error, "Failed to resume session: #{inspect(reason)}"}
    end
  end

  defp resolve_selector(selector) do
    case Integer.parse(selector) do
      {n, ""} when n > 0 ->
        sessions = SessionStore.list_recent(10)

        case Enum.at(sessions, n - 1) do
          nil -> selector
          s -> s.id
        end

      _ ->
        selector
    end
  end

  defp format_ago(datetime) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
