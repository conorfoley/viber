defmodule Viber.Server.SessionHandler do
  @moduledoc """
  Session lifecycle management for HTTP API.
  """

  alias Viber.Runtime.{Permissions, Session}

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

        browser_context = params["browser_context"] || %{}

        permission_mode =
          case params["permission_mode"] do
            nil -> Application.get_env(:viber, :server_permission_mode, :prompt)
            mode -> Permissions.mode_from_string(mode)
          end

        task =
          Task.Supervisor.async_nolink(Viber.TaskSupervisor, fn ->
            Viber.Runtime.Conversation.run(
              session: pid,
              model: model,
              user_input: user_input,
              event_handler: event_handler,
              permission_mode: permission_mode,
              browser_context: browser_context
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
