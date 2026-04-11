defmodule Viber.Server.SessionHandler do
  @moduledoc """
  Session lifecycle management for HTTP API.
  """

  alias Viber.Runtime.Session

  @spec create_session(map()) :: {:ok, map()} | {:error, term()}
  def create_session(params) do
    id = Integer.to_string(System.unique_integer([:monotonic, :positive]))
    opts = [id: id, name: {:via, Registry, {Viber.SessionRegistry, id}}]

    case DynamicSupervisor.start_child(Viber.SessionSupervisor, {Session, opts}) do
      {:ok, _pid} ->
        model = params["model"] || "sonnet"
        {:ok, %{id: id, model: model}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec send_message(String.t(), map(), (Viber.Runtime.Conversation.event() -> :ok)) ::
          {:ok, pid()} | {:error, term()}
  def send_message(session_id, params, event_handler) do
    case Registry.lookup(Viber.SessionRegistry, session_id) do
      [{pid, _}] ->
        user_input = params["message"] || ""
        model = params["model"] || "sonnet"

        task =
          Task.Supervisor.async_nolink(Viber.TaskSupervisor, fn ->
            Viber.Runtime.Conversation.run(
              session: pid,
              model: model,
              user_input: user_input,
              event_handler: event_handler,
              permission_mode: :allow
            )
          end)

        {:ok, task.pid}

      [] ->
        {:error, :not_found}
    end
  end

  @spec get_session(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_session(session_id) do
    case Registry.lookup(Viber.SessionRegistry, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
