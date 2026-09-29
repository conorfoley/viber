defmodule Viber.Runtime.Admission do
  @moduledoc """
  Bounded concurrency pools for work started from outside a session.

  Each pool (`:gateway`, `:scheduler`, `:server`, `:sub_agent`, ...) has a
  limit read from `config :viber, :admission, gateway: 4, ...`. A pool with
  no configured limit is unlimited and not tracked.

  `acquire/2` takes a slot for a holder process (the caller by default) or
  returns `{:error, :busy}` when the pool is full. Slots are released by
  `release/2`, handed to another process with `transfer/3`, and freed
  automatically when the holder exits.
  """

  use GenServer

  @type pool :: atom()
  @type limits :: %{optional(pool()) => pos_integer()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec acquire(pool(), keyword()) :: :ok | {:error, :busy}
  def acquire(pool, opts \\ []) when is_atom(pool) do
    GenServer.call(server(opts), {:acquire, pool, holder(opts)})
  end

  @spec release(pool(), keyword()) :: :ok
  def release(pool, opts \\ []) when is_atom(pool) do
    GenServer.call(server(opts), {:release, pool, holder(opts)})
  end

  @spec transfer(pool(), pid(), keyword()) :: :ok | {:error, :not_held}
  def transfer(pool, to, opts \\ []) when is_atom(pool) and is_pid(to) do
    GenServer.call(server(opts), {:transfer, pool, holder(opts), to})
  end

  @spec run(pool(), (-> result), keyword()) :: result | {:error, :busy} when result: term()
  def run(pool, fun, opts \\ []) when is_function(fun, 0) do
    with :ok <- acquire(pool, opts) do
      try do
        fun.()
      after
        release(pool, opts)
      end
    end
  end

  @spec stats(keyword()) :: %{pool() => %{in_use: non_neg_integer(), limit: pos_integer()}}
  def stats(opts \\ []), do: GenServer.call(server(opts), :stats)

  @impl true
  def init(opts) do
    limits =
      opts
      |> Keyword.get_lazy(:limits, fn -> Application.get_env(:viber, :admission, []) end)
      |> Map.new()

    {:ok, %{limits: limits, counts: %{}, holders: %{}}}
  end

  @impl true
  def handle_call({:acquire, pool, pid}, _from, state) do
    case Map.fetch(state.limits, pool) do
      :error ->
        {:reply, :ok, state}

      {:ok, limit} ->
        if Map.get(state.counts, pool, 0) >= limit do
          {:reply, {:error, :busy}, state}
        else
          {:reply, :ok, hold(state, pool, pid)}
        end
    end
  end

  def handle_call({:release, pool, pid}, _from, state) do
    state =
      case find_hold(state, pool, pid) do
        nil ->
          state

        ref ->
          Process.demonitor(ref, [:flush])
          drop(state, ref)
      end

    {:reply, :ok, state}
  end

  def handle_call({:transfer, pool, from, to}, _from, state) do
    cond do
      not Map.has_key?(state.limits, pool) ->
        {:reply, :ok, state}

      ref = find_hold(state, pool, from) ->
        Process.demonitor(ref, [:flush])
        {:reply, :ok, state |> drop(ref) |> hold(pool, to)}

      true ->
        {:reply, {:error, :not_held}, state}
    end
  end

  def handle_call(:stats, _from, state) do
    stats =
      Map.new(state.limits, fn {pool, limit} ->
        {pool, %{in_use: Map.get(state.counts, pool, 0), limit: limit}}
      end)

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, drop(state, ref)}
  end

  defp hold(state, pool, pid) do
    ref = Process.monitor(pid)

    %{
      state
      | holders: Map.put(state.holders, ref, {pool, pid}),
        counts: Map.update(state.counts, pool, 1, &(&1 + 1))
    }
  end

  defp drop(state, ref) do
    case Map.pop(state.holders, ref) do
      {nil, _} ->
        state

      {{pool, _pid}, holders} ->
        %{state | holders: holders, counts: Map.update!(state.counts, pool, &(&1 - 1))}
    end
  end

  defp find_hold(state, pool, pid) do
    Enum.find_value(state.holders, fn
      {ref, {^pool, ^pid}} -> ref
      _ -> nil
    end)
  end

  defp server(opts), do: Keyword.get(opts, :server, __MODULE__)
  defp holder(opts), do: Keyword.get(opts, :holder, self())
end
