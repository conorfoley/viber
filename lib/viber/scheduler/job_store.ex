defmodule Viber.Scheduler.JobStore do
  @moduledoc """
  Ecto-backed persistence for scheduled job definitions.
  Loads persisted jobs into Quantum on startup and provides CRUD operations.
  """

  use GenServer

  require Logger

  alias Viber.Repo
  alias Viber.Scheduler.{Job, Runner}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec list_jobs() :: [Job.t()]
  def list_jobs do
    GenServer.call(__MODULE__, :list_jobs)
  end

  @spec get_job(String.t()) :: {:ok, Job.t()} | {:error, String.t()}
  def get_job(id) do
    GenServer.call(__MODULE__, {:get_job, id})
  end

  @spec get_job_by_name(String.t()) :: {:ok, Job.t()} | {:error, String.t()}
  def get_job_by_name(name) do
    GenServer.call(__MODULE__, {:get_job_by_name, name})
  end

  @spec create_job(map()) :: {:ok, Job.t()} | {:error, Ecto.Changeset.t()}
  def create_job(attrs) do
    GenServer.call(__MODULE__, {:create_job, attrs})
  end

  @spec update_job(String.t(), map()) :: {:ok, Job.t()} | {:error, term()}
  def update_job(id, attrs) do
    GenServer.call(__MODULE__, {:update_job, id, attrs})
  end

  @spec delete_job(String.t()) :: :ok | {:error, String.t()}
  def delete_job(id) do
    GenServer.call(__MODULE__, {:delete_job, id})
  end

  @spec enable_job(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def enable_job(id), do: update_job(id, %{enabled: true})

  @spec disable_job(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def disable_job(id), do: update_job(id, %{enabled: false})

  @spec record_run(String.t(), String.t(), String.t() | nil) :: :ok
  def record_run(id, status, _output \\ nil) do
    GenServer.cast(__MODULE__, {:record_run, id, status})
  end

  @spec history(String.t() | nil, non_neg_integer()) :: [map()]
  def history(job_id \\ nil, limit \\ 20) do
    GenServer.call(__MODULE__, {:history, job_id, limit})
  end

  @impl true
  def init(_opts) do
    send(self(), :load_jobs)
    {:ok, %{history: []}}
  end

  @impl true
  def handle_info(:load_jobs, state) do
    if repo_available?() do
      try do
        jobs = Repo.all(Job)

        Enum.each(jobs, fn job ->
          if job.enabled, do: schedule_quantum_job(job)
        end)

        Logger.info("Loaded #{length(jobs)} scheduled job(s)")
      rescue
        e ->
          Logger.warning("Could not load scheduled jobs: #{Exception.message(e)}")
      end
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:list_jobs, _from, state) do
    jobs = if repo_available?(), do: safe_query(fn -> Repo.all(Job) end, []), else: []
    {:reply, jobs, state}
  end

  def handle_call({:get_job, id}, _from, state) do
    result =
      case safe_query(fn -> Repo.get(Job, id) end, nil) do
        nil -> {:error, "Job not found: #{id}"}
        job -> {:ok, job}
      end

    {:reply, result, state}
  end

  def handle_call({:get_job_by_name, name}, _from, state) do
    result =
      case safe_query(fn -> Repo.get_by(Job, name: name) end, nil) do
        nil -> {:error, "Job not found: #{name}"}
        job -> {:ok, job}
      end

    {:reply, result, state}
  end

  def handle_call({:create_job, attrs}, _from, state) do
    changeset = Job.changeset(%Job{}, attrs)

    case Repo.insert(changeset) do
      {:ok, job} ->
        if job.enabled, do: schedule_quantum_job(job)
        {:reply, {:ok, job}, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  def handle_call({:update_job, id, attrs}, _from, state) do
    case safe_query(fn -> Repo.get(Job, id) end, nil) do
      nil ->
        {:reply, {:error, "Job not found: #{id}"}, state}

      job ->
        changeset = Job.changeset(job, attrs)

        case Repo.update(changeset) do
          {:ok, updated} ->
            deschedule_quantum_job(job.id)
            if updated.enabled, do: schedule_quantum_job(updated)
            {:reply, {:ok, updated}, state}

          {:error, changeset} ->
            {:reply, {:error, changeset}, state}
        end
    end
  end

  def handle_call({:delete_job, id}, _from, state) do
    case safe_query(fn -> Repo.get(Job, id) end, nil) do
      nil ->
        {:reply, {:error, "Job not found: #{id}"}, state}

      job ->
        deschedule_quantum_job(job.id)
        Repo.delete!(job)
        {:reply, :ok, state}
    end
  end

  def handle_call({:history, job_id, limit}, _from, state) do
    entries =
      state.history
      |> then(fn h ->
        if job_id, do: Enum.filter(h, &(&1.job_id == job_id)), else: h
      end)
      |> Enum.take(limit)

    {:reply, entries, state}
  end

  @impl true
  def handle_cast({:record_run, id, status}, state) do
    now = DateTime.utc_now()

    safe_query(
      fn ->
        case Repo.get(Job, id) do
          nil -> :ok
          job -> Repo.update!(Job.changeset(job, %{last_run_at: now, last_status: status}))
        end
      end,
      :ok
    )

    entry = %{job_id: id, status: status, ran_at: now}
    history = [entry | state.history] |> Enum.take(500)
    {:noreply, %{state | history: history}}
  end

  defp schedule_quantum_job(job) do
    case Crontab.CronExpression.Parser.parse(job.cron_expr) do
      {:ok, cron} ->
        quantum_job =
          Viber.Scheduler.new_job()
          |> Quantum.Job.set_name(String.to_atom("viber_job_#{job.id}"))
          |> Quantum.Job.set_schedule(cron)
          |> Quantum.Job.set_task({Runner, :run, [job.id]})

        Viber.Scheduler.add_job(quantum_job)

      {:error, reason} ->
        Logger.warning("Invalid cron expression for job #{job.name}: #{inspect(reason)}")
    end
  end

  defp deschedule_quantum_job(id) do
    Viber.Scheduler.delete_job(String.to_atom("viber_job_#{id}"))
  end

  defp repo_available? do
    Application.get_env(:viber, :enable_repo, true) && Process.whereis(Viber.Repo) != nil
  end

  defp safe_query(fun, default) do
    if repo_available?() do
      try do
        fun.()
      rescue
        _ -> default
      end
    else
      default
    end
  end
end
