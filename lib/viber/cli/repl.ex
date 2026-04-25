defmodule Viber.CLI.Repl do
  @moduledoc """
  Interactive REPL loop for the Viber CLI.
  """

  require Logger

  alias Viber.CLI.Renderer
  alias Viber.Commands.{Dispatcher, Parser, Result}
  alias Viber.Runtime.Conversation
  alias Viber.Runtime.Event
  alias Viber.Runtime.FileRefs
  alias Viber.Runtime.Permissions.Broker

  defmodule State do
    @moduledoc false
    @enforce_keys [:session, :model]
    defstruct [:session, :model, :config, :project_root, permission_mode: :prompt]

    @type t :: %__MODULE__{
            session: pid(),
            model: String.t(),
            config: map() | nil,
            permission_mode: atom(),
            project_root: String.t() | nil
          }
  end

  @spec run(keyword()) :: :ok
  def run(opts) do
    state = %State{
      session: Keyword.fetch!(opts, :session),
      model: Keyword.fetch!(opts, :model),
      config: Keyword.get(opts, :config),
      permission_mode: Keyword.get(opts, :permission_mode, :prompt),
      project_root: Keyword.get(opts, :project_root, File.cwd!())
    }

    loop(state)
  end

  defp loop(state) do
    case IO.gets(prompt(state)) do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      raw_input ->
        case String.trim(raw_input) do
          "" -> loop(state)
          trimmed -> loop(handle_input(trimmed, state))
        end
    end
  end

  defp prompt(state) do
    model = state.model
    [IO.ANSI.faint(), model, IO.ANSI.reset(), IO.ANSI.magenta(), " ❯ ", IO.ANSI.reset()]
  end

  defp handle_input(input, state) do
    if Parser.command?(input) do
      handle_command(input, state)
    else
      handle_message(input, state)
    end
  end

  defp handle_command(input, state) do
    case Parser.parse(input) do
      {:command, name, args} ->
        opts = command_opts(state)

        case Dispatcher.invoke(state.session, name, args, opts) do
          {:ok, %Result{} = result} ->
            apply_result(result, name, state)

          {:error, {:unknown_command, n}} ->
            IO.write(Renderer.render_error("Unknown command: /#{n}"))
            state

          {:error, reason} ->
            IO.write(Renderer.render_error(inspect_error(reason)))
            state
        end

      {:suggestion, _input, suggestions} ->
        IO.puts("Did you mean /#{List.first(suggestions)}?")
        state

      {:not_command, _} ->
        IO.puts("Unknown command.")
        state
    end
  end

  defp apply_result(%Result{} = result, name, state) do
    if result.text not in [nil, ""], do: IO.puts(result.text)
    Enum.each(result.events, &handle_event/1)

    if name == "resume" do
      case Map.get(result.state_patch, :session) do
        pid when is_pid(pid) -> notify_resume(pid)
        _ -> :ok
      end
    end

    state = apply_state_patch(result.state_patch, state)

    case Map.get(result.state_patch, :retry_input) do
      nil ->
        state

      input ->
        IO.puts("Retrying: #{input}")
        handle_message(input, state)
    end
  end

  defp apply_state_patch(patch, state) when map_size(patch) == 0, do: state

  defp apply_state_patch(patch, state) do
    state
    |> maybe_put(:session, patch[:session])
    |> maybe_put(:model, patch[:model])
    |> maybe_put(:api_key, patch[:api_key])
  end

  defp maybe_put(state, _key, nil), do: state
  defp maybe_put(state, :session, pid) when is_pid(pid), do: %{state | session: pid}
  defp maybe_put(state, :model, model) when is_binary(model), do: %{state | model: model}

  defp maybe_put(state, :api_key, key) when is_binary(key) do
    config = state.config || %Viber.Runtime.Config{}
    %{state | config: %{config | api_key: key}}
  end

  defp maybe_put(state, _, _), do: state

  defp notify_resume(pid) when is_pid(pid) do
    msg_count = length(Viber.Runtime.Session.get_messages(pid))
    IO.puts("Resumed session (#{msg_count} messages). Continue where you left off.")
  end

  defp inspect_error(reason) when is_binary(reason), do: reason
  defp inspect_error(reason), do: inspect(reason)

  defp command_opts(state) do
    mcp_servers =
      Viber.Tools.MCP.ServerManager.list_servers()
      |> Map.new(fn {name, pid} -> {name, pid} end)

    %{
      model: state.model,
      config: state.config,
      permission_mode: state.permission_mode,
      project_root: state.project_root,
      mcp_servers: mcp_servers
    }
  end

  defp handle_message(input, state) do
    Logger.info("Repl: sending message, model=#{state.model}")

    input = expand_file_refs(input, state)

    spinner_ref = make_ref()
    spinner_active = :atomics.new(1, signed: false)
    :atomics.put(spinner_active, 1, 1)

    Owl.Spinner.start(
      id: spinner_ref,
      labels: [processing: Owl.Data.tag("Thinking...", :faint)]
    )

    event_handler = fn event ->
      if :atomics.get(spinner_active, 1) == 1 and event_stops_spinner?(event) do
        :atomics.put(spinner_active, 1, 0)
        Owl.Spinner.stop(id: spinner_ref, resolution: :ok)
      end

      handle_event(event)
      :ok
    end

    case Conversation.run(
           session: state.session,
           model: state.model,
           user_input: input,
           config: state.config,
           event_handler: event_handler,
           permission_mode: state.permission_mode,
           project_root: state.project_root
         ) do
      {:ok, _result} ->
        if :atomics.get(spinner_active, 1) == 1 do
          :atomics.put(spinner_active, 1, 0)
          Owl.Spinner.stop(id: spinner_ref, resolution: :ok)
        end

        Logger.debug("Repl: message completed successfully")
        IO.puts("")

      {:error, err} ->
        if :atomics.get(spinner_active, 1) == 1 do
          :atomics.put(spinner_active, 1, 0)
          Owl.Spinner.stop(id: spinner_ref, resolution: :error)
        end

        Logger.error("Repl: message failed: #{inspect(err)}")
        IO.write(Renderer.render_error(inspect(err)))
    end

    state
  end

  defp event_stops_spinner?(%Event{type: type})
       when type in [:text_delta, :tool_use_start, :thinking_delta, :error],
       do: true

  defp event_stops_spinner?(_), do: false

  defp handle_event(%Event{type: :text_delta, payload: %{text: text, sub_agent_id: _}}) do
    IO.write(Renderer.render_sub_agent_text_delta(text))
  end

  defp handle_event(%Event{type: :text_delta, payload: %{text: text}}), do: IO.write(text)

  defp handle_event(%Event{type: :tool_use_start, payload: %{name: "spawn_agent", id: id}}) do
    IO.write(Renderer.render_tool_use("spawn_agent", id))

    Owl.Spinner.start(
      id: {:sub_agent, id},
      labels: [processing: Owl.Data.tag("  ↳ Sub-agent working...", :faint)]
    )
  end

  defp handle_event(%Event{
         type: :tool_use_start,
         payload: %{name: name, id: id, sub_agent_id: _}
       }) do
    IO.write(Renderer.render_sub_agent_tool_use(name, id))
  end

  defp handle_event(%Event{type: :tool_use_start, payload: %{name: name, id: id}}) do
    IO.write(Renderer.render_tool_use(name, id))
  end

  defp handle_event(%Event{
         type: :tool_result,
         payload: %{name: "spawn_agent", id: id, output: output, is_error: is_error}
       }) do
    Owl.Spinner.stop(id: {:sub_agent, id}, resolution: if(is_error, do: :error, else: :ok))
    IO.write(Renderer.render_tool_result(output, is_error))
  end

  defp handle_event(%Event{
         type: :tool_result,
         payload: %{output: output, is_error: is_error, sub_agent_id: _}
       }) do
    IO.write(Renderer.render_sub_agent_tool_result(output, is_error))
  end

  defp handle_event(%Event{type: :tool_result, payload: %{output: output, is_error: is_error}}) do
    IO.write(Renderer.render_tool_result(output, is_error))
  end

  defp handle_event(%Event{type: :thinking_delta, payload: %{text: text, sub_agent_id: _}}) do
    IO.write(Renderer.render_sub_agent_thinking(text))
  end

  defp handle_event(%Event{type: :thinking_delta, payload: %{text: text}}) do
    IO.write(Renderer.render_thinking(text))
  end

  defp handle_event(%Event{type: :turn_complete, payload: %{usage: usage}}) do
    IO.write(Renderer.render_usage(usage))
  end

  defp handle_event(%Event{type: :error, payload: %{message: message}}) do
    IO.write(Renderer.render_error(message))
  end

  defp handle_event(%Event{
         type: :permission_request,
         payload: %{request_id: request_id, tool: tool, input: input}
       }) do
    decision = Renderer.prompt_permission(tool, input)
    Broker.resolve(request_id, decision)
  end

  defp handle_event(event) do
    Logger.debug("Repl: unhandled event #{inspect(event)}")
    :ok
  end

  defp expand_file_refs(input, state) do
    project_root = state.project_root || File.cwd!()

    Regex.replace(~r/@([^\s]+)/, input, fn full_token, pattern ->
      results = FileRefs.resolve_pattern(pattern, project_root)
      {combined, errors} = FileRefs.format_results(results)

      Enum.each(errors, fn err -> IO.puts("Warning: #{err}") end)

      if combined == "" do
        full_token
      else
        combined
      end
    end)
  end
end
