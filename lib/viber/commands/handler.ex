defmodule Viber.Commands.Handler do
  @moduledoc """
  Behaviour implemented by every slash command handler under
  `Viber.Commands.Handlers.*`.

  Handlers expose a single transport-agnostic entry point — `run/3` —
  returning a `Viber.Commands.Result` so the dispatcher can relay the
  outcome to any frontend (REPL, HTTP, gateway).

  Each handler module that `use`s this behaviour gets a default `run/3`
  that delegates to its existing `execute/2` and translates legacy return
  shapes (`{:ok, text}`, `{:error, reason}`, `{:retry, input}`,
  `{:resume, pid}`, `{:update_toolsets, list}`) into the canonical
  `Result` struct. Handlers may override `run/3` to take full control
  (emit events, customise state patches).
  """

  alias Viber.Commands.Result

  @callback run(session :: pid() | nil, args :: [String.t()], opts :: map()) ::
              {:ok, Result.t()} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Viber.Commands.Handler

      @impl Viber.Commands.Handler
      def run(session, args, opts) do
        Viber.Commands.Handler.__default_run__(__MODULE__, session, args, opts)
      end

      defoverridable run: 3
    end
  end

  @doc false
  @spec __default_run__(module(), pid() | nil, [String.t()], map()) ::
          {:ok, Result.t()} | {:error, term()}
  def __default_run__(handler, session, args, opts) do
    context = Map.put(opts, :session, session)

    case handler.execute(args, context) do
      {:ok, text} -> {:ok, %Result{text: text}}
      {:error, reason} -> {:error, reason}
      {:retry, input} -> {:ok, %Result{state_patch: %{retry_input: input}}}
      {:resume, pid} when is_pid(pid) -> {:ok, %Result{state_patch: %{session: pid}}}
      {:update_toolsets, list} -> {:ok, %Result{state_patch: %{enabled_toolsets: list}}}
      other -> {:error, {:unexpected_handler_return, other}}
    end
  end
end
