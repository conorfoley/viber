defmodule Viber.Server.Interrupts do
  @moduledoc """
  Tracks per-session interrupt flags for in-flight conversation turns started
  via the HTTP API.

  Each active turn owns an `:atomics` reference; setting its first slot to `1`
  signals the conversation loop to abort at the next iteration boundary. The
  reference is stored in a public ETS table so HTTP callers (in other
  processes) can flip the flag without going through the session process.
  """

  use GenServer

  @table :viber_server_interrupts

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Create a new interrupt ref for `session_id`, replacing any previous ref.
  Returns the fresh `:atomics` reference the caller should hand to
  `Conversation.run/1`.
  """
  @spec register(String.t()) :: :atomics.atomics_ref()
  def register(session_id) do
    ref = :atomics.new(1, signed: false)
    :ets.insert(@table, {session_id, ref})
    ref
  end

  @doc """
  Signal the current in-flight turn for `session_id` to interrupt.
  Returns `:ok` even if no interrupt ref is registered.
  """
  @spec signal(String.t()) :: :ok | {:error, :not_found}
  def signal(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, ref}] ->
        :atomics.put(ref, 1, 1)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc "Remove the interrupt ref for a session (after the turn completes)."
  @spec clear(String.t()) :: :ok
  def clear(session_id) do
    :ets.delete(@table, session_id)
    :ok
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
