defmodule Viber.Runtime.Permissions.Broker do
  @moduledoc """
  Permission broker: mediates between the conversation loop (which asks whether
  a tool call should be allowed) and the frontend (which presents the request
  to a human or policy engine and responds with a decision).

  The broker is transport-agnostic. A caller requests approval via
  `request/5` passing an event handler used to emit the `:permission_request`
  event; the call blocks until `resolve/3` is invoked with a matching
  `request_id` or the timeout elapses (which is treated as `:deny`).

  Pending requests are tied to the caller pid via `Process.monitor/1`; if the
  caller dies before a decision arrives, its entry is cleaned up automatically.

  Decisions:

    * `:allow` — run this tool call only.
    * `:deny` — refuse this tool call.
    * `:always_allow` — run this and future calls to the same tool in this turn.
  """

  use GenServer

  require Logger

  alias Viber.Runtime.Event

  @default_timeout 300_000

  @type decision :: :allow | :deny | :always_allow

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  @doc """
  Request permission for a tool invocation.

  Blocks the caller until a decision is resolved or the timeout elapses.
  On timeout the decision is `:deny` and any later `resolve/3` call for the
  same `request_id` returns `{:error, :not_found}`. If the event handler
  raises, throws, or exits, the pending entry is cancelled and `:deny` is
  returned.
  """
  @spec request(
          String.t() | nil,
          String.t(),
          String.t(),
          (Event.t() -> any()),
          keyword()
        ) :: decision()
  def request(session_id, tool_name, input, event_handler, opts \\ [])
      when is_function(event_handler, 1) do
    server = Keyword.get(opts, :server, __MODULE__)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    request_id = generate_id()

    :ok = GenServer.call(server, {:register, request_id, self(), session_id})

    event =
      Event.new(
        :permission_request,
        %{request_id: request_id, tool: tool_name, input: input},
        session_id: session_id
      )

    try do
      event_handler.(event)
      wait_for_decision(server, request_id, timeout)
    catch
      kind, reason ->
        Logger.error(
          "Broker: permission event handler failed (#{inspect(kind)}): #{inspect(reason)}"
        )

        GenServer.cast(server, {:cancel, request_id})
        :deny
    end
  end

  @doc """
  Resolve a pending permission request with a decision.

  When `:session_id` is passed in `opts`, the resolution only succeeds if it
  matches the session that originated the request (prevents accidental
  cross-session resolution on a shared broker).
  """
  @spec resolve(String.t(), decision(), keyword()) ::
          :ok | {:error, :not_found} | {:error, :session_mismatch}
  def resolve(request_id, decision, opts \\ []) when decision in [:allow, :deny, :always_allow] do
    server = Keyword.get(opts, :server, __MODULE__)
    session_id = Keyword.get(opts, :session_id)
    GenServer.call(server, {:resolve, request_id, decision, session_id})
  end

  @doc """
  List pending request ids (for diagnostics / tests).
  """
  @spec pending(keyword()) :: [String.t()]
  def pending(opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, :pending)
  end

  @impl true
  def init(:ok) do
    {:ok, %{pending: %{}, monitors: %{}}}
  end

  @impl true
  def handle_call({:register, request_id, caller, session_id}, _from, state) do
    ref = Process.monitor(caller)

    pending =
      Map.put(state.pending, request_id, %{
        caller: caller,
        monitor: ref,
        session_id: session_id
      })

    monitors = Map.put(state.monitors, ref, request_id)
    {:reply, :ok, %{state | pending: pending, monitors: monitors}}
  end

  def handle_call({:resolve, request_id, decision, session_id}, _from, state) do
    case Map.get(state.pending, request_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{session_id: origin} when not is_nil(session_id) and origin != session_id ->
        {:reply, {:error, :session_mismatch}, state}

      %{caller: caller, monitor: ref} ->
        Process.demonitor(ref, [:flush])
        send(caller, {:permission_decision, request_id, decision})
        pending = Map.delete(state.pending, request_id)
        monitors = Map.delete(state.monitors, ref)
        {:reply, :ok, %{state | pending: pending, monitors: monitors}}
    end
  end

  def handle_call(:pending, _from, state) do
    {:reply, Map.keys(state.pending), state}
  end

  @impl true
  def handle_cast({:cancel, request_id}, state) do
    case Map.pop(state.pending, request_id) do
      {nil, _} ->
        {:noreply, state}

      {%{monitor: ref}, pending} ->
        Process.demonitor(ref, [:flush])
        {:noreply, %{state | pending: pending, monitors: Map.delete(state.monitors, ref)}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {request_id, monitors} ->
        Logger.debug(
          "Broker: caller for request #{request_id} died (#{inspect(reason)}); cleaning up"
        )

        {:noreply, %{state | pending: Map.delete(state.pending, request_id), monitors: monitors}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp wait_for_decision(server, request_id, timeout) do
    receive do
      {:permission_decision, ^request_id, decision} -> decision
    after
      timeout ->
        Logger.warning("Broker: permission request #{request_id} timed out after #{timeout}ms")
        GenServer.cast(server, {:cancel, request_id})

        receive do
          {:permission_decision, ^request_id, _} -> :ok
        after
          0 -> :ok
        end

        :deny
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
