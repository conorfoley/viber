defmodule Viber.Runtime.Emitter do
  @moduledoc """
  Stamps and delivers the events of one conversation run.

  Every event passed to `emit/2` gets the run's `run_id` (unless it already
  carries one, e.g. an event forwarded from a sub-agent run), the run's
  `session_id` when missing, and a `seq` that increases by one per event
  within the run.

  A sink that raises, throws or exits never breaks the run: the failure is
  reported to the owner process as
  `{:viber_event_sink_failed, run_id, %{seq: seq, type: type, reason: reason}}`.
  """

  require Logger

  alias Viber.Runtime.{Errors, Event}

  @type sink :: (Event.t() -> term())

  @type t :: %__MODULE__{
          run_id: String.t(),
          session_id: String.t() | nil,
          sink: sink(),
          owner: pid(),
          counter: :atomics.atomics_ref()
        }

  @enforce_keys [:run_id, :sink, :owner, :counter]
  defstruct [:run_id, :session_id, :sink, :owner, :counter]

  @spec new(sink(), keyword()) :: t()
  def new(sink, opts \\ []) when is_function(sink, 1) do
    %__MODULE__{
      run_id: Keyword.get_lazy(opts, :run_id, &generate_run_id/0),
      session_id: Keyword.get(opts, :session_id),
      sink: sink,
      owner: Keyword.get(opts, :owner, self()),
      counter: :atomics.new(1, signed: false)
    }
  end

  @spec emit(t(), Event.t()) :: :ok
  def emit(%__MODULE__{} = emitter, %Event{} = event) do
    event = stamp(emitter, event)
    deliver(emitter, event, event.seq, event.type)
  end

  def emit(%__MODULE__{} = emitter, other), do: deliver(emitter, other, nil, nil)

  defp deliver(emitter, event, seq, type) do
    emitter.sink.(event)
    :ok
  catch
    kind, value ->
      reason = Errors.from_caught(kind, value, __STACKTRACE__)
      Logger.warning("Emitter: event sink failed for #{type}: #{Errors.message(reason)}")

      send(
        emitter.owner,
        {:viber_event_sink_failed, emitter.run_id, %{seq: seq, type: type, reason: reason}}
      )

      :ok
  end

  @spec handler(t()) :: (Event.t() -> :ok)
  def handler(%__MODULE__{} = emitter), do: &emit(emitter, &1)

  @spec generate_run_id() :: String.t()
  def generate_run_id do
    "run_" <> (:crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false))
  end

  defp stamp(emitter, event) do
    %{
      event
      | run_id: event.run_id || emitter.run_id,
        session_id: event.session_id || emitter.session_id,
        seq: :atomics.add_get(emitter.counter, 1, 1)
    }
  end
end
