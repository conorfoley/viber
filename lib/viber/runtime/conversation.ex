defmodule Viber.Runtime.Conversation do
  @moduledoc """
  Conversation loop orchestrating LLM interaction, tool execution, and session management.
  """

  require Logger

  alias Viber.API.{Client, MessageRequest}
  alias Viber.Runtime.{Compact, Event, Permissions, Prompt, Session, SubAgent, Usage}
  alias Viber.Runtime.Permissions.Broker
  alias Viber.Runtime.Conversation.{Context, Request, StreamAccumulator}
  alias Viber.Tools.{Executor, Registry, Spec}

  @type event :: Event.t()

  @default_max_iterations 25

  @spec run(Request.t() | keyword() | map()) :: {:ok, term()} | {:error, term()}
  def run(%Request{} = req) do
    max_iter =
      req.max_iterations ||
        config_max_iterations(req.config) ||
        @default_max_iterations

    ctx = %Context{
      session: req.session,
      model: req.model,
      config: req.config,
      event_handler: req.event_handler,
      permission_mode: req.permission_mode,
      project_root: req.project_root,
      provider_module: req.provider_module,
      browser_context: req.browser_context,
      interrupt: req.interrupt,
      enabled_toolsets: req.enabled_toolsets,
      max_iterations: max_iter
    }

    user_input = req.user_input
    Logger.info("Conversation.run: model=#{ctx.model} input=#{String.slice(user_input, 0..80)}")

    user_msg = %{role: :user, blocks: [{:text, user_input}], usage: nil}
    :ok = Session.add_message(ctx.session, user_msg)

    turn_loop(ctx, 0)
  end

  def run(opts) when is_list(opts) or is_map(opts), do: run(Request.new(opts))

  defp turn_loop(%Context{event_handler: handler, max_iterations: max}, iteration)
       when iteration >= max do
    handler.(Event.new(:error, %{message: "Maximum iterations (#{max}) exceeded"}))
    {:error, :max_iterations}
  end

  defp turn_loop(%Context{interrupt: interrupt, event_handler: handler} = ctx, iteration)
       when interrupt != nil do
    if :atomics.get(interrupt, 1) == 1 do
      Logger.info("Conversation: interrupted by user at iteration #{iteration}")
      handler.(Event.new(:interrupted, %{message: "Interrupted"}))
      {:ok, :interrupted}
    else
      do_turn_loop(ctx, iteration)
    end
  end

  defp turn_loop(%Context{} = ctx, iteration), do: do_turn_loop(ctx, iteration)

  defp do_turn_loop(%Context{} = ctx, iteration) do
    maybe_auto_compact(ctx)
    messages = Session.get_messages(ctx.session)

    system_prompt =
      Prompt.build(
        config: ctx.config,
        permission_mode: ctx.permission_mode,
        project_root: ctx.project_root,
        browser_context: ctx.browser_context
      )

    Logger.debug(
      "Conversation: system prompt ~#{Prompt.estimate_tokens(system_prompt)} tokens (#{String.length(system_prompt)} chars)"
    )

    tool_defs =
      Registry.builtin_specs()
      |> filter_by_toolsets(ctx.enabled_toolsets)
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
        ctx.event_handler.(Event.new(:error, %{message: inspect(err)}))
        {:error, err}
    end
  end

  defp do_stream(request, %Context{provider_module: nil, model: model, config: config}) do
    Client.stream_message(model, request, config_overrides(config))
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
      ctx.event_handler.(Event.new(:turn_complete, %{usage: usage}))
      {:ok, %{text: text_content, usage: usage, iterations: iteration + 1}}
    else
      Logger.info(
        "Conversation: executing #{length(tool_uses)} tool(s): #{Enum.map_join(tool_uses, ", ", fn {_id, name, _input} -> name end)}"
      )

      {tool_results, ctx} = execute_tools(tool_uses, ctx)

      tool_result_blocks =
        Enum.map(tool_results, fn {id, name, output, is_error} ->
          {:tool_result, id, name, output, is_error}
        end)

      tool_msg = %{role: :user, blocks: tool_result_blocks, usage: nil}
      :ok = Session.add_message(ctx.session, tool_msg)

      turn_loop(ctx, iteration + 1)
    end
  end

  defp execute_tools(tool_uses, %Context{} = ctx) do
    permission_mode = ctx.permission_mode
    event_handler = ctx.event_handler
    session_id = safe_session_id(ctx.session)

    active_specs = Registry.builtin_specs() |> filter_by_toolsets(ctx.enabled_toolsets)

    specs_by_name =
      active_specs
      |> Map.new(fn spec -> {spec.name, spec} end)

    base_policy =
      Enum.reduce(active_specs, Permissions.new_policy(permission_mode), fn spec, pol ->
        Permissions.register_tool(pol, spec.name, spec.permission)
      end)

    {decisions, newly_allowed} =
      Enum.reduce(tool_uses, {[], MapSet.new()}, fn {id, name, input_map}, {acc, allowed_set} ->
        input_str = if is_binary(input_map), do: input_map, else: Jason.encode!(input_map)
        input = ensure_parsed_input(input_map)

        policy =
          case Map.get(specs_by_name, name) do
            %Spec{permission_fn: fun} = spec when fun != nil ->
              effective = Spec.effective_permission(spec, input)
              Permissions.register_tool(base_policy, name, effective)

            _ ->
              base_policy
          end

        already_allowed =
          MapSet.member?(ctx.allowed_tools, name) or MapSet.member?(allowed_set, name)

        case Permissions.check(policy, name, input_str) do
          permission when permission in [:allow, :prompt] ->
            if permission == :allow or already_allowed do
              {[{:run, id, name, input} | acc], allowed_set}
            else
              broker_result =
                try do
                  Broker.request(session_id, name, input_str, event_handler)
                catch
                  :exit, _ -> :deny
                end

              case broker_result do
                :allow ->
                  {[{:run, id, name, input} | acc], allowed_set}

                :always_allow ->
                  {[{:run, id, name, input} | acc], MapSet.put(allowed_set, name)}

                :deny ->
                  reason = "tool '#{name}' denied by user"
                  {[{:denied, id, name, reason} | acc], allowed_set}
              end
            end

          {:deny, reason} ->
            {[{:denied, id, name, reason} | acc], allowed_set}
        end
      end)

    decisions = Enum.reverse(decisions)
    ctx = %{ctx | allowed_tools: MapSet.union(ctx.allowed_tools, newly_allowed)}

    run_sequential? =
      Enum.any?(decisions, fn
        {:run, _id, name, _input} ->
          case Map.get(specs_by_name, name) do
            %Spec{concurrent: false} -> true
            _ -> false
          end

        _ ->
          false
      end)

    results =
      if run_sequential? do
        Enum.map(decisions, &run_decision(&1, ctx, event_handler))
      else
        ctx.task_supervisor
        |> Task.Supervisor.async_stream_nolink(
          decisions,
          &run_decision(&1, ctx, event_handler),
          ordered: true,
          timeout: 300_000
        )
        |> Enum.zip(decisions)
        |> Enum.map(fn
          {{:ok, result}, _} ->
            result

          {{:exit, reason}, {:run, id, name, _}} ->
            {id, name, "Tool execution failed: #{inspect(reason)}", true}

          {{:exit, reason}, {:denied, id, name, _}} ->
            {id, name, "Tool execution failed: #{inspect(reason)}", true}
        end)
      end

    {results, ctx}
  end

  defp run_decision({:run, id, "spawn_agent", input}, ctx, event_handler) do
    event_handler.(Event.new(:tool_use_start, %{name: "spawn_agent", id: id}))

    case SubAgent.run(input, ctx) do
      {:ok, %{text: text}} ->
        event_handler.(
          Event.new(:tool_result, %{name: "spawn_agent", id: id, output: text, is_error: false})
        )

        {id, "spawn_agent", text, false}

      {:error, reason} ->
        msg = "Sub-agent failed: #{inspect(reason)}"

        event_handler.(
          Event.new(:tool_result, %{name: "spawn_agent", id: id, output: msg, is_error: true})
        )

        {id, "spawn_agent", msg, true}
    end
  end

  defp run_decision({:run, id, name, input}, _ctx, event_handler) do
    event_handler.(Event.new(:tool_use_start, %{name: name, id: id}))

    case Executor.execute(name, input) do
      {:ok, output} ->
        event_handler.(
          Event.new(:tool_result, %{name: name, id: id, output: output, is_error: false})
        )

        {id, name, output, false}

      {:error, error} ->
        event_handler.(
          Event.new(:tool_result, %{name: name, id: id, output: error, is_error: true})
        )

        {id, name, error, true}
    end
  end

  defp run_decision({:denied, id, name, reason}, _ctx, event_handler) do
    event_handler.(Event.new(:tool_result, %{name: name, id: id, output: reason, is_error: true}))

    {id, name, reason, true}
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
        handler.(Event.new(:text_delta, %{text: text}))
        %{acc | blocks: Map.put(acc.blocks, idx, %{block | text: block.text <> text})}

      {%{type: :tool_use} = block, %{type: "input_json_delta", partial_json: json}} ->
        %{acc | blocks: Map.put(acc.blocks, idx, %{block | input: block.input <> json})}

      {%{type: :thinking} = block, %{type: "thinking_delta", thinking: text}} ->
        handler.(Event.new(:thinking_delta, %{text: text}))
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

    handler.(
      Event.new(:error, %{
        message:
          "Stream interrupted: #{if is_exception(e), do: Exception.message(e), else: inspect(e)}"
      })
    )

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

  defp safe_session_id(session) do
    Session.get_id(session)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp filter_by_toolsets(specs, nil), do: specs
  defp filter_by_toolsets(specs, []), do: specs

  defp filter_by_toolsets(specs, toolsets) do
    toolset_set = MapSet.new(toolsets)
    Enum.filter(specs, fn spec -> MapSet.member?(toolset_set, spec.toolset) end)
  end

  defp config_overrides(nil), do: []

  defp config_overrides(%Viber.Runtime.Config{} = config) do
    []
    |> then(fn opts ->
      if config.base_url, do: [{:base_url, config.base_url} | opts], else: opts
    end)
    |> then(fn opts ->
      if is_binary(config.api_key) and config.api_key != "",
        do: [{:api_key, config.api_key} | opts],
        else: opts
    end)
  end

  defp config_overrides(_), do: []

  defp config_max_iterations(%Viber.Runtime.Config{max_iterations: val}) when is_integer(val),
    do: val

  defp config_max_iterations(_), do: nil

  @auto_compact_threshold 80_000

  defp maybe_auto_compact(%Context{session: session, model: model, event_handler: handler}) do
    if Compact.should_compact?(session, token_threshold: @auto_compact_threshold) do
      Logger.info("Conversation: auto-compacting (token threshold exceeded)")
      handler.(Event.new(:info, %{message: "Auto-compacting conversation history..."}))

      {:ok, removed} = Compact.compact(session, model: model)
      Logger.info("Conversation: auto-compacted #{removed} messages")
    end
  end
end
