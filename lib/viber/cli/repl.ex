defmodule Viber.CLI.Repl do
  @moduledoc """
  Interactive REPL loop for the Viber CLI.
  """

  require Logger

  alias Viber.CLI.Renderer
  alias Viber.Commands.Parser
  alias Viber.Runtime.Conversation

  @spec run(keyword()) :: :ok
  def run(opts) do
    session = Keyword.fetch!(opts, :session)
    model = Keyword.fetch!(opts, :model)
    config = Keyword.get(opts, :config)
    permission_mode = Keyword.get(opts, :permission_mode, :prompt)
    project_root = Keyword.get(opts, :project_root, File.cwd!())

    loop(%{
      session: session,
      model: model,
      config: config,
      permission_mode: permission_mode,
      project_root: project_root
    })
  end

  defp loop(state) do
    case IO.gets("viber> ") do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      input ->
        input = String.trim(input)

        if input == "" do
          loop(state)
        else
          state = handle_input(input, state)
          loop(state)
        end
    end
  end

  defp handle_input(input, state) do
    if Parser.is_command?(input) do
      handle_command(input, state)
    else
      handle_message(input, state)
    end
  end

  defp handle_command(input, state) do
    case Parser.parse(input) do
      {:command, name, args} ->
        {:ok, spec} = Viber.Commands.Registry.get(name)
        context = build_command_context(state)

        case spec.handler.execute(args, context) do
          {:ok, output} ->
            IO.puts(output)

          {:error, error} ->
            IO.write(Renderer.render_error(error))
        end

        if name == "model" and args != [] do
          %{state | model: List.first(args)}
        else
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

    event_handler = fn event ->
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
        Logger.debug("Repl: message completed successfully")
        IO.puts("")

      {:error, err} ->
        Logger.error("Repl: message failed: #{inspect(err)}")
        IO.write(Renderer.render_error(inspect(err)))
    end

    state
  end

  defp handle_event({:text_delta, text}), do: IO.write(text)

  defp handle_event({:tool_use_start, name, id}) do
    IO.write(Renderer.render_tool_use(name, id))
  end

  defp handle_event({:tool_result, name, output, is_error}) do
    _ = name
    IO.write(Renderer.render_tool_result(output, is_error))
  end

  defp handle_event({:thinking_delta, text}) do
    IO.write([IO.ANSI.faint(), text, IO.ANSI.reset()])
  end

  defp handle_event({:turn_complete, usage}) do
    IO.write(Renderer.render_usage(usage))
  end

  defp handle_event({:error, message}) do
    IO.write(Renderer.render_error(message))
  end

  defp handle_event(_), do: :ok

  defp build_command_context(state) do
    %{
      session: state.session,
      model: state.model,
      config: state.config,
      permission_mode: state.permission_mode
    }
  end
end
