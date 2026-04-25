defmodule Viber.Commands.Dispatcher do
  @moduledoc """
  Transport-agnostic entry point for slash commands.

  `invoke/4` looks up the handler in `Viber.Commands.Registry`, builds an
  options map suitable for the handler, and returns a
  `Viber.Commands.Result` (or `{:error, reason}`).

  Frontends should never call individual handler modules directly; they
  invoke through the dispatcher and react to `Result.text`,
  `Result.events`, and `Result.state_patch`.
  """

  alias Viber.Commands.{Registry, Result}
  alias Viber.Runtime.{Event, Session}

  @type opts :: %{
          optional(:model) => String.t(),
          optional(:config) => term(),
          optional(:permission_mode) => atom(),
          optional(:project_root) => String.t(),
          optional(:enabled_toolsets) => [atom()] | nil,
          optional(:mcp_servers) => map()
        }

  @spec invoke(pid() | nil, String.t(), [String.t()], keyword() | map()) ::
          {:ok, Result.t()} | {:error, term()}
  def invoke(session, name, args, opts \\ []) do
    opts_map = normalize_opts(opts)

    case Registry.get(name) do
      {:ok, spec} ->
        ctx = build_context(session, opts_map)

        try do
          case spec.handler.run(session, args, ctx) do
            {:ok, %Result{} = result} ->
              {:ok, post_process(spec, args, session, ctx, result)}

            {:error, _} = err ->
              err

            other ->
              {:error, {:unexpected_handler_return, other}}
          end
        rescue
          e -> {:error, {:handler_crash, Exception.message(e)}}
        end

      :error ->
        {:error, {:unknown_command, name}}
    end
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts

  defp build_context(session, opts) do
    %{
      session: session,
      session_id: session && safe_session_id(session),
      model: Map.get(opts, :model),
      config: Map.get(opts, :config),
      permission_mode: Map.get(opts, :permission_mode, :prompt),
      project_root: Map.get(opts, :project_root),
      enabled_toolsets: Map.get(opts, :enabled_toolsets),
      mcp_servers: Map.get(opts, :mcp_servers, %{})
    }
  end

  defp safe_session_id(pid) when is_pid(pid) do
    Session.get_id(pid)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp safe_session_id(_), do: nil

  # `/model <name>` — apply model switch on the session and patch state.
  defp post_process(%{name: "model"}, [first | _], session, ctx, result)
       when first != "list" do
    if session do
      try do
        Session.set_model(session, first)
      catch
        :exit, _ -> :ok
      end
    end

    sid = ctx.session_id

    events =
      result.events ++
        [Event.new(:model_changed, %{model: first}, session_id: sid)]

    %{
      result
      | state_patch: Map.put(result.state_patch, :model, first),
        events: events
    }
  end

  # `/clear` — emit a cleared event so remote frontends drop transcript state.
  defp post_process(%{name: "clear"}, _args, _session, ctx, result) do
    sid = ctx.session_id

    events =
      result.events ++
        [Event.new(:session_cleared, %{}, session_id: sid)]

    %{result | state_patch: Map.put(result.state_patch, :cleared, true), events: events}
  end

  defp post_process(_spec, _args, _session, _ctx, result), do: result
end
