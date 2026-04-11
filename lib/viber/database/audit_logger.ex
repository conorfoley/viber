defmodule Viber.Database.AuditLogger do
  @moduledoc """
  Logs every query executed through Viber to the query_log table.
  Falls back to Logger if the repo is unavailable.
  """

  require Logger

  alias Viber.Database.QueryLog
  alias Viber.Repo

  @spec log_query(map()) :: :ok
  def log_query(attrs) do
    if repo_available?() do
      Task.Supervisor.start_child(Viber.TaskSupervisor, fn ->
        changeset = QueryLog.changeset(%QueryLog{}, attrs)

        case Repo.insert(changeset) do
          {:ok, _} -> :ok
          {:error, cs} -> Logger.debug("Failed to log query: #{inspect(cs.errors)}")
        end
      end)
    else
      Logger.info(
        "Query audit: #{attrs[:connection_name]} | #{attrs[:query_type]} | #{attrs[:execution_time_ms]}ms | #{attrs[:status]}"
      )
    end

    :ok
  end

  @spec recent(keyword()) :: [QueryLog.t()]
  def recent(opts \\ []) do
    if repo_available?() do
      import Ecto.Query

      limit = Keyword.get(opts, :limit, 50)
      conn = Keyword.get(opts, :connection)
      session = Keyword.get(opts, :session_id)

      query =
        from(q in QueryLog,
          order_by: [desc: q.inserted_at],
          limit: ^limit
        )

      query =
        if conn do
          from(q in query, where: q.connection_name == ^conn)
        else
          query
        end

      query =
        if session do
          from(q in query, where: q.session_id == ^session)
        else
          query
        end

      Repo.all(query)
    else
      []
    end
  end

  defp repo_available? do
    Application.get_env(:viber, :enable_repo, true) && Process.whereis(Viber.Repo) != nil
  end
end
