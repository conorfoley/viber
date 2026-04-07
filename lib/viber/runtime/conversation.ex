defmodule Viber.Runtime.Conversation do
  @moduledoc """
  Conversation loop orchestrating LLM interaction, tool execution, and session management.
  """

  require Logger

  alias Viber.API.{Client, MessageRequest}
  alias Viber.Runtime.{Permissions, Prompt, Session, Usage}
  alias Viber.Runtime.Conversation.{Context, StreamAccumulator}
  alias Viber.Tools.{Executor, Registry, Spec}

  @type event ::
          {:text_delta, String.t()}
          | {:tool_use_start, String.t(), String.t()}
          | {:tool_result, String.t(), String.t(), boolean()}
          | {:thinking_delta, String.t()}
          | {:turn_complete, Usage.t()}
          | {:error, String.t()}

  @max_iterations 25

  @spec run(keyword()) :: {:ok, term()} | {:error, term()}
  def run(opts) do
    ctx = %Context{
      session: Keyword.fetch!(opts, :session),
      model: Keyword.fetch!(opts, :model),
      config: Keyword.get(opts, :config),
      event_handler: Keyword.get(opts, :event_handler, fn _event -> :ok end),
      permission_mode: Keyword.get(opts, :permission_mode, :prompt),
      project_root: Keyword.get(opts, :project_root, File.cwd!()),
      provider_module: Keyword.get(opts, :provider_module)
    }

    user_input = Keyword.fetch!(opts, :user_input)
    Logger.info("Conversation.run: model=#{ctx.model} input=#{String.slice(user_input, 0..80)}")

    user_msg = %{role: :user, blocks: [{:text, user_input}], usage: nil}
    :ok = Session.add_message(ctx.session, user_msg)

    turn_loop(ctx, 0)
  end

  defp turn_loop(%Context{event_handler: handler}, iteration) when iteration >= @max_iterations do
    handler.({:error, "Maximum iterations (#{@max_iterations}) exceeded"})
    {:error, :max_iterations}
  end

  defp turn_loop(%Context{} = ctx, iteration) do
    messages = Session.get_messages(ctx.session)

    system_prompt =
      Prompt.build(
        config: ctx.config,
        permission_mode: ctx.permission_mode,
        project_root: ctx.project_root
      )

    tool_defs =
      Registry.builtin_specs()
      |> Enum.map(&Spec.to_tool_definition/1)

    api_messages = Enum.map(messages, &to_api_message/1)

    request = %MessageRequest{
      model: Client.resolve_model_alias(ctx.model),
      max_tokens: Client.max_tokens_for_model(ctx.model),
      messages: api_messages,
      system: system_prompt,
      tools: tool_defs,
      stream: true
    }

    Logger.debug(
      "Conversation turn_loop: iteration=#{iteration} messages=#{length(messages)} tools=#{length(tool_defs)}"
    )

    case do_stream(request, ctx) do
      {:ok, stream} ->
        Logger.debug("Conversation turn_loop: stream started, processing events")
        acc = process_stream(stream, ctx.event_handler)
        Logger.debug("Conversation turn_loop: stream complete, handling result")
        handle_turn_result(acc, ctx, iteration)

      {:error, err} ->
        Logger.error("Conversation turn_loop: stream error #{inspect(err)}")
        ctx.event_handler.({:error, inspect(err)})
        {:error, err}
    end
  end

  defp do_stream(request, %Context{provider_module: nil, model: model}) do
    Client.stream_message(model, request)
  end

  defp do_stream(request, %Context{provider_module: provider_module}) do
    provider_module.stream_message(request)
  end

  defp handle_turn_result(%StreamAccumulator{stream_error: error}, _ctx, _iteration)
       when not is_nil(error) do
    Logger.error("Conversation: aborting turn due to stream error: #{inspect(error)}")
    {:error, {:stream_error, error}}
  end

  defp handle_turn_result(acc, %Context{} = ctx, iteration) do
    tool_uses = extract_tool_uses(acc.blocks)
    text_content = extract_text(acc.blocks)

    usage =
      case acc.current_usage do
        nil -> %Usage{}
        api_usage -> Usage.from_api_usage(api_usage)
      end

    assistant_blocks =
      Enum.flat_map(acc.blocks, fn
        {_idx, %{type: :text, text: text}} ->
          [{:text, text}]

        {_idx, %{type: :tool_use, id: id, name: name, input: input}} ->
          parsed = parse_tool_input(input)
          [{:tool_use, id, name, parsed}]

        _ ->
          []
      end)

    assistant_msg = %{role: :assistant, blocks: assistant_blocks, usage: usage}
    :ok = Session.add_message(ctx.session, assistant_msg)

    if tool_uses == [] do
      Logger.debug("Conversation: turn complete, no tool calls")
      ctx.event_handler.({:turn_complete, usage})
      {:ok, %{text: text_content, usage: usage, iterations: iteration + 1}}
    else
      Logger.info(
        "Conversation: executing #{length(tool_uses)} tool(s): #{Enum.map_join(tool_uses, ", ", fn {_id, name, _input} -> name end)}"
      )

      tool_results = execute_tools(tool_uses, ctx.permission_mode, ctx.event_handler)

      tool_result_blocks =
        Enum.map(tool_results, fn {id, name, output, is_error} ->
          {:tool_result, id, name, output, is_error}
        end)

      tool_msg = %{role: :user, blocks: tool_result_blocks, usage: nil}
      :ok = Session.add_message(ctx.session, tool_msg)

      turn_loop(ctx, iteration + 1)
    end
  end

  defp execute_tools(tool_uses, permission_mode, event_handler) do
    policy =
      Enum.reduce(Registry.builtin_specs(), Permissions.new_policy(permission_mode), fn spec,
                                                                                        pol ->
        Permissions.register_tool(pol, spec.name, spec.permission)
      end)

    Viber.TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      tool_uses,
      fn {id, name, input_map} ->
        event_handler.({:tool_use_start, name, id})

        input_str = if is_binary(input_map), do: input_map, else: Jason.encode!(input_map)

        case Permissions.check(policy, name, input_str) do
          permission when permission in [:allow, :prompt] ->
            allowed =
              permission == :allow || Permissions.prompt_user(name, input_str)

            if allowed do
              input = ensure_parsed_input(input_map)

              case Executor.execute(name, input) do
                {:ok, output} ->
                  event_handler.({:tool_result, name, output, false})
                  {id, name, output, false}

                {:error, error} ->
                  event_handler.({:tool_result, name, error, true})
                  {id, name, error, true}
              end
            else
              reason = "tool '#{name}' denied by user"
              event_handler.({:tool_result, name, reason, true})
              {id, name, reason, true}
            end

          {:deny, reason} ->
            event_handler.({:tool_result, name, reason, true})
            {id, name, reason, true}
        end
      end,
      ordered: true,
      timeout: 120_000
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {nil, "unknown", "Tool execution failed: #{inspect(reason)}", true}
    end)
  end

  defp parse_tool_input(input) when is_binary(input) do
    case Jason.decode(input) do
      {:ok, map} when is_map(map) -> map
      _ -> %{"raw" => input}
    end
  end

  defp parse_tool_input(input) when is_map(input), do: input

  defp ensure_parsed_input(input) when is_map(input), do: input
  defp ensure_parsed_input(input) when is_binary(input), do: parse_tool_input(input)

  defp to_api_message(%{role: role, blocks: blocks}) do
    api_role =
      case role do
        :user -> "user"
        :assistant -> "assistant"
        :system -> "user"
        :tool -> "user"
      end

    content = Enum.map(blocks, &block_to_api_content/1)
    %Viber.API.InputMessage{role: api_role, content: content}
  end

  defp block_to_api_content({:text, text}), do: %{type: "text", text: text}

  defp block_to_api_content({:tool_use, id, name, input}) do
    %{type: "tool_use", id: id, name: name, input: input}
  end

  defp block_to_api_content({:tool_result, tool_use_id, _tool_name, output, is_error}) do
    result = %{
      type: "tool_result",
      tool_use_id: tool_use_id,
      content: [%{type: "text", text: output}]
    }

    if is_error, do: Map.put(result, :is_error, true), else: result
  end

  defp process_stream(stream, event_handler) do
    Enum.reduce(stream, %StreamAccumulator{}, fn event, acc ->
      process_event(event, acc, event_handler)
    end)
  end

  defp process_event({:message_start, response}, acc, _handler) do
    Logger.debug("Stream event: message_start")
    %{acc | response: response}
  end

  defp process_event({:content_block_start, idx, block}, acc, _handler) do
    Logger.debug(
      "Stream event: content_block_start idx=#{idx} type=#{Map.get(block, :type, "?")}"
    )

    block_state =
      case block do
        %{type: "text"} ->
          %{type: :text, text: ""}

        %{type: "tool_use", id: id, name: name} ->
          %{type: :tool_use, id: id, name: name, input: ""}

        %{type: "thinking"} ->
          %{type: :thinking, text: ""}

        _ ->
          %{type: :unknown}
      end

    %{acc | blocks: Map.put(acc.blocks, idx, block_state)}
  end

  defp process_event({:content_block_delta, idx, delta}, acc, handler) do
    case {Map.get(acc.blocks, idx), delta} do
      {%{type: :text} = block, %{type: "text_delta", text: text}} ->
        handler.({:text_delta, text})
        %{acc | blocks: Map.put(acc.blocks, idx, %{block | text: block.text <> text})}

      {%{type: :tool_use} = block, %{type: "input_json_delta", partial_json: json}} ->
        %{acc | blocks: Map.put(acc.blocks, idx, %{block | input: block.input <> json})}

      {%{type: :thinking} = block, %{type: "thinking_delta", thinking: text}} ->
        handler.({:thinking_delta, text})
        %{acc | blocks: Map.put(acc.blocks, idx, %{block | text: block.text <> text})}

      _ ->
        acc
    end
  end

  defp process_event({:content_block_stop, idx}, acc, _handler) do
    Logger.debug("Stream event: content_block_stop idx=#{idx}")
    acc
  end

  defp process_event({:message_delta, _delta, usage}, acc, _handler) do
    Logger.debug("Stream event: message_delta")
    %{acc | current_usage: usage}
  end

  defp process_event(:message_stop, acc, _handler) do
    Logger.debug("Stream event: message_stop")
    acc
  end

  defp process_event({:stream_error, e}, acc, handler) do
    Logger.error("Conversation: stream error received: #{inspect(e)}")
    handler.({:error, "Stream interrupted: #{Exception.message(e)}"})
    %{acc | stream_error: e}
  end

  defp process_event(other, acc, _handler) do
    Logger.debug("Stream event: unknown #{inspect(other)}")
    acc
  end

  defp extract_tool_uses(blocks) do
    blocks
    |> Enum.sort_by(fn {idx, _} -> idx end)
    |> Enum.flat_map(fn
      {_idx, %{type: :tool_use, id: id, name: name, input: input}} -> [{id, name, input}]
      _ -> []
    end)
  end

  defp extract_text(blocks) do
    blocks
    |> Enum.sort_by(fn {idx, _} -> idx end)
    |> Enum.flat_map(fn
      {_idx, %{type: :text, text: text}} -> [text]
      _ -> []
    end)
    |> Enum.join()
  end
end
