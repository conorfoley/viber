defmodule Viber.Gateway.Router do
  @moduledoc """
  Central GenServer that routes inbound channel messages to Viber sessions and
  dispatches outbound messages back to the originating adapter.

  ## Presence

  A named ETS table (`#{inspect(:viber_gateway_presence)}`) maps
  `{adapter_id, channel_id, user_id}` to a `session_id` string. Sessions are
  created on demand and re-used across subsequent messages from the same user
  in the same channel, giving each user a persistent conversation thread.

  ## Fan-out

  `broadcast/1` sends a text message to every channel that has previously seen
  inbound traffic. Adapters added via `register_adapter/3` are eligible for
  both inbound routing and proactive outbound delivery.
  """

  use GenServer

  require Logger

  alias Viber.Gateway.Message
  alias Viber.Runtime.{Conversation, Session}

  @presence_table :viber_gateway_presence

  @type adapter_entry :: %{module: module(), config: map()}
  @type state :: %{
          adapters: %{atom() => adapter_entry()},
          channels: MapSet.t({atom(), String.t()})
        }

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec register_adapter(atom(), module(), map()) :: :ok
  def register_adapter(adapter_id, module, config) do
    GenServer.call(__MODULE__, {:register_adapter, adapter_id, module, config})
  end

  @spec inbound(Message.t()) :: :ok
  def inbound(%Message{} = message) do
    GenServer.cast(__MODULE__, {:inbound, message})
  end

  @spec send_to_channel(atom(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def send_to_channel(adapter_id, channel_id, text, opts \\ []) do
    GenServer.call(__MODULE__, {:send_to_channel, adapter_id, channel_id, text, opts})
  end

  @spec broadcast(String.t()) :: :ok
  def broadcast(text) do
    GenServer.cast(__MODULE__, {:broadcast, text})
  end

  @spec known_channels() :: [{atom(), String.t()}]
  def known_channels do
    GenServer.call(__MODULE__, :known_channels)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@presence_table, [:named_table, :public, :set])
    state = %{adapters: %{}, channels: MapSet.new()}
    {:ok, state, {:continue, :register_adapters_from_config}}
  end

  @impl true
  def handle_continue(:register_adapters_from_config, state) do
    state = maybe_register_discord(state)
    {:noreply, state}
  end

  @impl true
  def handle_call({:register_adapter, adapter_id, module, config}, _from, state) do
    entry = %{module: module, config: config}
    {:reply, :ok, put_in(state, [:adapters, adapter_id], entry)}
  end

  @impl true
  def handle_call({:send_to_channel, adapter_id, channel_id, text, opts}, _from, state) do
    result =
      case Map.get(state.adapters, adapter_id) do
        nil -> {:error, :adapter_not_found}
        %{module: mod, config: cfg} -> mod.send_message(cfg, channel_id, text, opts)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:known_channels, _from, state) do
    {:reply, Enum.to_list(state.channels), state}
  end

  @impl true
  def handle_cast({:inbound, %Message{} = msg}, state) do
    state = track_channel(state, msg.adapter_id, msg.channel_id)
    session_pid = ensure_session(msg)
    adapter_entry = Map.get(state.adapters, msg.adapter_id)
    dispatch_conversation(session_pid, msg, adapter_entry)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast, text}, state) do
    Enum.each(state.channels, fn {adapter_id, channel_id} ->
      case Map.get(state.adapters, adapter_id) do
        nil -> :ok
        %{module: mod, config: cfg} -> mod.send_message(cfg, channel_id, text, [])
      end
    end)

    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp maybe_register_discord(state) do
    discord_cfg = Application.get_env(:viber, :discord, [])
    bot_token = Keyword.get(discord_cfg, :bot_token)
    public_key = Keyword.get(discord_cfg, :public_key)

    if bot_token && public_key do
      config = Map.new(discord_cfg)

      Logger.info("Gateway: registering Discord adapter")

      maybe_register_discord_commands(config)

      put_in(state, [:adapters, :discord], %{
        module: Viber.Gateway.Discord.Adapter,
        config: config
      })
    else
      state
    end
  end

  defp maybe_register_discord_commands(config) do
    if config[:application_id] do
      Task.Supervisor.start_child(Viber.TaskSupervisor, fn ->
        case Viber.Gateway.Discord.Adapter.register_commands(config) do
          :ok -> Logger.info("Gateway: Discord slash commands registered")
          {:error, reason} -> Logger.warning("Gateway: Discord command registration failed: #{inspect(reason)}")
        end
      end)
    end
  end

  defp track_channel(state, adapter_id, channel_id) do
    %{state | channels: MapSet.put(state.channels, {adapter_id, channel_id})}
  end

  defp ensure_session(%Message{adapter_id: adapter_id, channel_id: channel_id, user_id: user_id}) do
    presence_key = {adapter_id, channel_id, user_id}

    case :ets.lookup(@presence_table, presence_key) do
      [{^presence_key, session_id}] ->
        case Registry.lookup(Viber.SessionRegistry, session_id) do
          [{pid, _}] -> pid
          [] -> create_and_register_session(presence_key)
        end

      [] ->
        create_and_register_session(presence_key)
    end
  end

  defp create_and_register_session(presence_key) do
    {adapter_id, channel_id, user_id} = presence_key

    session_id =
      "gw_#{adapter_id}_#{channel_id}_#{user_id}_#{:erlang.unique_integer([:positive])}"

    opts = [
      id: session_id,
      name: {:via, Registry, {Viber.SessionRegistry, session_id}}
    ]

    {:ok, pid} = DynamicSupervisor.start_child(Viber.SessionSupervisor, {Session, opts})
    :ets.insert(@presence_table, {presence_key, session_id})

    Logger.info("Gateway: created session #{session_id} for #{inspect(presence_key)}")

    pid
  end

  defp dispatch_conversation(session_pid, %Message{} = msg, adapter_entry) do
    Task.Supervisor.start_child(Viber.TaskSupervisor, fn ->
      buffer = accumulate_response(session_pid, msg)

      cond do
        adapter_entry == nil ->
          Logger.warning("Gateway: no adapter entry for #{msg.adapter_id}, dropping response")

        buffer == "" ->
          Logger.warning("Gateway: empty response for message #{msg.id}")
          send_reply(adapter_entry, msg, "(no response)")

        true ->
          send_reply(adapter_entry, msg, buffer)
      end
    end)
  end

  defp send_reply(%{module: mod, config: cfg}, %Message{} = msg, text) do
    mod.send_message(cfg, msg.channel_id, text, reply_context: msg.metadata)
  end

  defp accumulate_response(session_pid, %Message{} = msg) do
    caller = self()

    event_handler = fn event ->
      send(caller, {:gw_event, event})
      :ok
    end

    {:ok, task_pid} =
      Task.Supervisor.start_child(Viber.TaskSupervisor, fn ->
        Conversation.run(
          session: session_pid,
          model: Application.get_env(:viber, :gateway_model, "sonnet"),
          user_input: msg.text,
          event_handler: event_handler,
          permission_mode: :allow
        )
      end)

    monitor_ref = Process.monitor(task_pid)
    collect_text(monitor_ref, "")
  end

  defp collect_text(monitor_ref, buffer) do
    receive do
      {:gw_event, {:text_delta, text}} ->
        collect_text(monitor_ref, buffer <> text)

      {:gw_event, {:turn_complete, _usage}} ->
        buffer

      {:gw_event, {:error, reason}} ->
        Logger.error("Gateway: conversation error: #{reason}")
        buffer

      {:gw_event, _other} ->
        collect_text(monitor_ref, buffer)

      {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
        buffer
    after
      300_000 ->
        Logger.warning("Gateway: conversation timed out")
        buffer
    end
  end
end
