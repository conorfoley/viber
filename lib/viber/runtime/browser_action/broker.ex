defmodule Viber.Runtime.BrowserAction.Broker do
  @moduledoc """
  Browser action broker: suspends the conversation loop while a browser
  extension executes a tool action client-side.

  The broker is modelled on `Viber.Runtime.Permissions.Broker`. A caller
  registers an action via `request/4`, which:

  1. Emits a `:browser_action` SSE event so the extension receives it immediately.
  2. Blocks the calling process until `resolve/3` is called (by the router when
     the extension POSTs a result) or the timeout elapses.

  On timeout the call returns `{:error, :timeout}`. The extension result is
  returned as `{:ok, %{"output" => String.t(), "is_error" => boolean()}}`.

  Pending requests are monitored; if the caller dies before a result arrives
  the entry is cleaned up automatically.
  """

  use GenServer

  require Logger

  alias Viber.Runtime.{BrowserAction, Event}

  @default_timeout 30_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  @doc """
  Request a browser action from the connected extension.

  Emits a `:browser_action` event via `event_handler`, then blocks the caller
  until the extension posts a result or the timeout elapses.

  Returns `{:ok, result_map}` or `{:error, :timeout}`.
  """
  @spec request(
          String.t() | nil,
          String.t(),
          map(),
          (Event.t() -> any()),
          keyword()
        ) :: {:ok, map()} | {:error, :timeout}
  def request(session_id, tool_name, input, event_handler, opts \\ [])
      when is_function(event_handler, 1) do
    server = Keyword.get(opts, :server, __MODULE__)

    timeout =
      Keyword.get(
        opts,
        :timeout,
        Application.get_env(:viber, :browser_toolset, [])
        |> Keyword.get(:action_timeout_ms, @default_timeout)
      )

    action = BrowserAction.new(session_id, tool_name, input)

    :ok = GenServer.call(server, {:register, action.id, self(), session_id})

    event =
      Event.new(
        :browser_action,
        %{action_id: action.id, tool_name: tool_name, input: input},
        session_id: session_id
      )

    Logger.info(
      "BrowserAction.Broker: requesting action=#{tool_name} id=#{action.id} session=#{inspect(session_id)} timeout=#{timeout}ms"
    )

    try do
      event_handler.(event)
      result = wait_for_result(server, action.id, timeout)

      case result do
        {:ok, %{"output" => output, "is_error" => is_error}} ->
          Logger.info(
            "BrowserAction.Broker: resolved action=#{tool_name} id=#{action.id} is_error=#{is_error} output_bytes=#{byte_size(output)}"
          )

        _ ->
          :ok
      end

      result
    catch
      kind, reason ->
        Logger.error(
          "BrowserAction.Broker: event handler failed (#{inspect(kind)}): #{inspect(reason)}"
        )

        GenServer.cast(server, {:cancel, action.id})
        {:error, :timeout}
    end
  end

  @doc """
  Resolve a pending browser action with the extension's result.

  `result` should be a map with `"output"` (string) and `"is_error"` (boolean).
  Optionally pass `session_id:` to guard against cross-session resolution.
  """
  @spec resolve(String.t(), map(), keyword()) ::
          :ok | {:error, :not_found} | {:error, :session_mismatch}
  def resolve(action_id, result, opts \\ []) when is_map(result) do
    server = Keyword.get(opts, :server, __MODULE__)
    session_id = Keyword.get(opts, :session_id)
    GenServer.call(server, {:resolve, action_id, result, session_id})
  end

  @doc "List pending action ids (for diagnostics / tests)."
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
  def handle_call({:register, action_id, caller, session_id}, _from, state) do
    ref = Process.monitor(caller)

    pending =
      Map.put(state.pending, action_id, %{
        caller: caller,
        monitor: ref,
        session_id: session_id
      })

    monitors = Map.put(state.monitors, ref, action_id)
    {:reply, :ok, %{state | pending: pending, monitors: monitors}}
  end

  def handle_call({:resolve, action_id, result, session_id}, _from, state) do
    case Map.get(state.pending, action_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{session_id: origin} when not is_nil(session_id) and origin != session_id ->
        {:reply, {:error, :session_mismatch}, state}

      %{caller: caller, monitor: ref} ->
        Process.demonitor(ref, [:flush])
        send(caller, {:browser_action_result, action_id, result})
        pending = Map.delete(state.pending, action_id)
        monitors = Map.delete(state.monitors, ref)
        {:reply, :ok, %{state | pending: pending, monitors: monitors}}
    end
  end

  def handle_call(:pending, _from, state) do
    {:reply, Map.keys(state.pending), state}
  end

  @impl true
  def handle_cast({:cancel, action_id}, state) do
    case Map.pop(state.pending, action_id) do
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

      {action_id, monitors} ->
        Logger.debug(
          "BrowserAction.Broker: caller for action #{action_id} died (#{inspect(reason)}); cleaning up"
        )

        {:noreply, %{state | pending: Map.delete(state.pending, action_id), monitors: monitors}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp wait_for_result(server, action_id, timeout) do
    receive do
      {:browser_action_result, ^action_id, result} -> {:ok, result}
    after
      timeout ->
        Logger.warning("BrowserAction.Broker: action #{action_id} timed out after #{timeout}ms")

        GenServer.cast(server, {:cancel, action_id})

        receive do
          {:browser_action_result, ^action_id, _} -> :ok
        after
          0 -> :ok
        end

        {:error, :timeout}
    end
  end
end
