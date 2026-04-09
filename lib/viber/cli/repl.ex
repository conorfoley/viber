defmodule Viber.CLI.Repl do
  @moduledoc """
  Interactive REPL loop for the Viber CLI.
  """

  require Logger

  alias Viber.CLI.Renderer
  alias Viber.Commands.Parser
  alias Viber.Runtime.Conversation
  alias Viber.Runtime.FileRefs

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
        case Viber.Commands.Registry.get(name) do
          {:ok, spec} ->
            context = build_command_context(state)

            case spec.handler.execute(args, context) do
              {:ok, output} ->
                IO.puts(output)

                if name == "model" and args != [] do
                  new_model = List.first(args)
                  Viber.Runtime.Session.set_model(state.session, new_model)
                  %{state | model: new_model}
                else
                  state
                end

              {:error, error} ->
                IO.write(Renderer.render_error(error))
                state

              {:resume, new_session} ->
                msg_count = length(Viber.Runtime.Session.get_messages(new_session))
                IO.puts("Resumed session (#{msg_count} messages). Continue where you left off.")
                %{state | session: new_session}
            end

          :error ->
            IO.write(Renderer.render_error("Unknown command: /#{name}"))
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

  defp event_stops_spinner?({:text_delta, _}), do: true
  defp event_stops_spinner?({:tool_use_start, _, _}), do: true
  defp event_stops_spinner?({:thinking_delta, _}), do: true
  defp event_stops_spinner?({:error, _}), do: true
  defp event_stops_spinner?(_), do: false

  defp handle_event({:text_delta, text}), do: IO.write(text)

  defp handle_event({:tool_use_start, name, id}) do
    IO.write(Renderer.render_tool_use(name, id))
  end

  defp handle_event({:tool_result, name, output, is_error}) do
    _ = name
    IO.write(Renderer.render_tool_result(output, is_error))
  end

  defp handle_event({:thinking_delta, text}) do
    IO.write(Renderer.render_thinking(text))
  end

  defp handle_event({:turn_complete, usage}) do
    IO.write(Renderer.render_usage(usage))
  end

  defp handle_event({:error, message}) do
    IO.write(Renderer.render_error(message))
  end

  defp handle_event(event) do
    Logger.debug("Repl: unhandled event #{inspect(event)}")
    :ok
  end

  defp build_command_context(state) do
    %{
      session: state.session,
      model: state.model,
      config: state.config,
      permission_mode: state.permission_mode,
      project_root: state.project_root
    }
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
