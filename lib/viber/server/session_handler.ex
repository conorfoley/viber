defmodule Viber.Server.SessionHandler do
  @moduledoc """
  Session lifecycle management for HTTP API.
  """

  alias Viber.Runtime.{Permissions, Session, SessionStore, Usage}
  alias Viber.Server.Interrupts

  @spec create_session(map()) :: {:ok, map()} | {:error, term()}
  def create_session(params) do
    id = Integer.to_string(System.unique_integer([:monotonic, :positive]))
    model = params["model"] || "sonnet"
    project_root = params["project_root"]

    opts = [
      id: id,
      model: model,
      project_root: project_root,
      name: {:via, Registry, {Viber.SessionRegistry, id}}
    ]

    case DynamicSupervisor.start_child(Viber.SessionSupervisor, {Session, opts}) do
      {:ok, _pid} ->
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

        browser_context = Viber.Runtime.BrowserContext.new(params["browser_context"])

        permission_mode =
          case params["permission_mode"] do
            nil -> Application.get_env(:viber, :server_permission_mode, :prompt)
            mode -> Permissions.mode_from_string(mode)
          end

        interrupt_ref = Interrupts.register(session_id)

        task =
          Task.Supervisor.async_nolink(Viber.TaskSupervisor, fn ->
            try do
              Viber.Runtime.Conversation.run(
                session: pid,
                model: model,
                user_input: user_input,
                event_handler: event_handler,
                permission_mode: permission_mode,
                browser_context: browser_context,
                interrupt: interrupt_ref
              )
            after
              Interrupts.clear(session_id)
            end
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

  @doc """
  List sessions: both active (registered in `Viber.SessionRegistry`) and
  recently persisted. Active sessions take precedence when ids overlap.
  """
  @spec list_sessions(non_neg_integer()) :: [map()]
  def list_sessions(limit \\ 50) do
    active =
      Registry.select(Viber.SessionRegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
      |> Enum.map(fn {id, pid} ->
        usage = safe_call(fn -> Session.get_usage(pid) end, %Usage{})
        messages = safe_call(fn -> Session.get_messages(pid) end, [])

        %{
          id: id,
          status: "active",
          model: safe_call(fn -> Session.get_model(pid) end, nil),
          message_count: length(messages),
          usage: usage_map(usage),
          last_activity: nil
        }
      end)

    active_ids = MapSet.new(active, & &1.id)

    persisted =
      SessionStore.list_recent(limit)
      |> Enum.reject(fn s -> MapSet.member?(active_ids, s.id) end)
      |> Enum.map(fn s ->
        %{
          id: s.id,
          status: "persisted",
          model: s.model,
          title: s.title,
          message_count: length(s.messages || []),
          usage: persisted_usage_map(s.usage),
          last_activity: s.updated_at && NaiveDateTime.to_iso8601(s.updated_at)
        }
      end)

    active ++ persisted
  end

  @spec session_info(String.t()) :: {:ok, map()} | {:error, :not_found}
  def session_info(session_id) do
    case get_session(session_id) do
      {:ok, pid} ->
        usage = Session.get_usage(pid)
        messages = Session.get_messages(pid)

        {:ok,
         %{
           id: session_id,
           status: "active",
           message_count: length(messages),
           usage: usage_map(usage)
         }}

      {:error, :not_found} ->
        case SessionStore.load_session(session_id) do
          {:ok, {messages, usage, meta}} ->
            {:ok,
             %{
               id: session_id,
               status: "persisted",
               model: meta[:model],
               message_count: length(messages),
               usage: usage_map(usage)
             }}

          _ ->
            {:error, :not_found}
        end
    end
  end

  @spec list_messages(String.t(), keyword()) :: {:ok, map()} | {:error, :not_found}
  def list_messages(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100) |> min(500) |> max(1)
    offset = Keyword.get(opts, :offset, 0) |> max(0)

    case fetch_messages(session_id) do
      {:ok, all} ->
        sliced = all |> Enum.drop(offset) |> Enum.take(limit)

        {:ok,
         %{
           session_id: session_id,
           total: length(all),
           limit: limit,
           offset: offset,
           messages: Enum.map(sliced, &message_to_map/1)
         }}

      :error ->
        {:error, :not_found}
    end
  end

  @spec delete_session(String.t(), keyword()) :: :ok | {:error, :not_found}
  def delete_session(session_id, opts \\ []) do
    purge? = Keyword.get(opts, :purge, false)

    case Registry.lookup(Viber.SessionRegistry, session_id) do
      [{pid, _}] ->
        Interrupts.clear(session_id)
        DynamicSupervisor.terminate_child(Viber.SessionSupervisor, pid)
        if purge?, do: SessionStore.delete_session(session_id)
        :ok

      [] ->
        if purge? do
          SessionStore.delete_session(session_id)
          :ok
        else
          case SessionStore.load_session(session_id) do
            {:ok, _} -> :ok
            _ -> {:error, :not_found}
          end
        end
    end
  end

  @spec resume_session(String.t()) :: {:ok, map()} | {:error, term()}
  def resume_session(session_id) do
    case Registry.lookup(Viber.SessionRegistry, session_id) do
      [{_pid, _}] ->
        {:error, :already_active}

      [] ->
        opts = [
          id: session_id,
          name: {:via, Registry, {Viber.SessionRegistry, session_id}}
        ]

        case SessionStore.load_session(session_id) do
          {:ok, _} ->
            case DynamicSupervisor.start_child(
                   Viber.SessionSupervisor,
                   {__MODULE__, {:resume_child, session_id, opts}}
                 ) do
              {:ok, _pid} -> {:ok, %{id: session_id, status: "resumed"}}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc false
  def child_spec({:resume_child, session_id, opts}) do
    %{
      id: {__MODULE__, session_id},
      start: {Session, :resume, [session_id, opts]},
      restart: :temporary
    }
  end

  @spec interrupt(String.t()) :: :ok | {:error, :not_found}
  def interrupt(session_id) do
    case Registry.lookup(Viber.SessionRegistry, session_id) do
      [{_pid, _}] -> Interrupts.signal(session_id)
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Invoke a slash command via `Viber.Commands.Dispatcher` and return a
  JSON-shaped result for HTTP clients.
  """
  @spec invoke_command(String.t(), String.t(), [String.t()], map()) ::
          {:ok, map()} | {:error, term()}
  def invoke_command(session_id, name, args, opts \\ %{}) do
    case Registry.lookup(Viber.SessionRegistry, session_id) do
      [{pid, _}] ->
        dispatch_opts = %{
          model: Map.get(opts, "model") || safe_call(fn -> Session.get_model(pid) end, nil),
          permission_mode: parse_permission_mode(Map.get(opts, "permission_mode")),
          project_root:
            Map.get(opts, "project_root") ||
              safe_call(fn -> Session.get_project_root(pid) end, nil),
          enabled_toolsets: Map.get(opts, "enabled_toolsets")
        }

        case Viber.Commands.Dispatcher.invoke(pid, name, args, dispatch_opts) do
          {:ok, result} -> {:ok, result_to_map(name, result)}
          {:error, reason} -> {:error, reason}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp parse_permission_mode(nil), do: :prompt
  defp parse_permission_mode(mode) when is_binary(mode), do: Permissions.mode_from_string(mode)
  defp parse_permission_mode(mode) when is_atom(mode), do: mode

  defp result_to_map(name, %Viber.Commands.Result{} = r) do
    %{
      name: name,
      text: text_to_string(r.text),
      events: Enum.map(r.events, &Viber.Runtime.Event.to_map/1),
      state_patch: state_patch_to_map(r.state_patch)
    }
  end

  defp text_to_string(nil), do: nil
  defp text_to_string(t) when is_binary(t), do: t
  defp text_to_string(t), do: IO.iodata_to_binary(t)

  defp state_patch_to_map(patch) do
    Map.new(patch, fn
      {:session, pid} when is_pid(pid) -> {"session", inspect(pid)}
      {:model, m} -> {"model", m}
      {:enabled_toolsets, list} -> {"enabled_toolsets", list}
      {:retry_input, input} -> {"retry_input", input}
      {:cleared, b} -> {"cleared", b}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp fetch_messages(session_id) do
    case get_session(session_id) do
      {:ok, pid} ->
        {:ok, Session.get_messages(pid)}

      {:error, :not_found} ->
        case SessionStore.load_session(session_id) do
          {:ok, {messages, _usage, _meta}} -> {:ok, messages}
          _ -> :error
        end
    end
  end

  defp message_to_map(%{role: role, blocks: blocks, usage: usage}) do
    %{
      role: Atom.to_string(role),
      blocks: Enum.map(blocks, &block_to_map/1),
      usage: if(usage, do: usage_map(usage), else: nil)
    }
  end

  defp block_to_map({:text, text}), do: %{type: "text", text: text}

  defp block_to_map({:tool_use, id, name, input}),
    do: %{type: "tool_use", id: id, name: name, input: input}

  defp block_to_map({:tool_result, tool_use_id, name, output, is_error}),
    do: %{
      type: "tool_result",
      tool_use_id: tool_use_id,
      name: name,
      output: output,
      is_error: is_error
    }

  defp usage_map(%Usage{} = u), do: Viber.Runtime.Event.usage_to_map(u)

  defp persisted_usage_map(%{} = m) do
    %{
      input_tokens: m["input_tokens"] || 0,
      output_tokens: m["output_tokens"] || 0,
      cache_creation_tokens: m["cache_creation_tokens"] || 0,
      cache_read_tokens: m["cache_read_tokens"] || 0,
      turns: m["turns"] || 0,
      total_tokens:
        (m["input_tokens"] || 0) + (m["output_tokens"] || 0) +
          (m["cache_creation_tokens"] || 0) + (m["cache_read_tokens"] || 0)
    }
  end

  defp persisted_usage_map(_), do: persisted_usage_map(%{})

  defp safe_call(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end
end
