defmodule Viber.Runtime.Conversation.StreamAccumulator do
  @moduledoc """
  Accumulates stream events into a complete response.
  """

  @type block_state ::
          %{type: :text, text: String.t()}
          | %{type: :tool_use, id: String.t(), name: String.t(), input: String.t()}
          | %{type: :thinking, text: String.t()}
          | %{type: :unknown}

  @type t :: %__MODULE__{
          response: Viber.API.MessageResponse.t() | nil,
          blocks: %{non_neg_integer() => block_state()},
          current_usage: Viber.API.Usage.t() | nil,
          stream_error: term() | nil
        }

  defstruct response: nil, blocks: %{}, current_usage: nil, stream_error: nil
end

defmodule Viber.Runtime.Conversation do
  @moduledoc """
  Conversation loop orchestrating LLM interaction, tool execution, and session management.
  """

  require Logger

  alias Viber.API.{Client, MessageRequest}
  alias Viber.Runtime.{Permissions, Prompt, Session, Usage}
  alias Viber.Runtime.Conversation.StreamAccumulator
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
    session = Keyword.fetch!(opts, :session)
    model = Keyword.fetch!(opts, :model)
    user_input = Keyword.fetch!(opts, :user_input)
    config = Keyword.get(opts, :config)
    event_handler = Keyword.get(opts, :event_handler, fn _event -> :ok end)
    permission_mode = Keyword.get(opts, :permission_mode, :prompt)
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    provider_module = Keyword.get(opts, :provider_module)

    Logger.info("Conversation.run: model=#{model} input=#{String.slice(user_input, 0..80)}")

    user_msg = %{role: :user, blocks: [{:text, user_input}], usage: nil}
    :ok = Session.add_message(session, user_msg)

    turn_loop(
      session,
      model,
      config,
      event_handler,
      permission_mode,
      project_root,
      provider_module,
      0
    )
  end

  defp turn_loop(
         _session,
         _model,
         _config,
         event_handler,
         _permission_mode,
         _project_root,
         _provider_module,
         iteration
       )
       when iteration >= @max_iterations do
    event_handler.({:error, "Maximum iterations (#{@max_iterations}) exceeded"})
    {:error, :max_iterations}
  end

  defp turn_loop(
         session,
         model,
         config,
         event_handler,
         permission_mode,
         project_root,
         provider_module,
         iteration
       ) do
    messages = Session.get_messages(session)

    system_prompt =
      Prompt.build(config: config, permission_mode: permission_mode, project_root: project_root)

    tool_defs =
      Registry.builtin_specs()
      |> Enum.map(&Spec.to_tool_definition/1)

    api_messages = Enum.map(messages, &to_api_message/1)

    request = %MessageRequest{
      model: Client.resolve_model_alias(model),
      max_tokens: Client.max_tokens_for_model(model),
      messages: api_messages,
      system: system_prompt,
      tools: tool_defs,
      stream: true
    }

    Logger.debug("Conversation turn_loop: iteration=#{iteration} messages=#{length(messages)} tools=#{length(tool_defs)}")

    case do_stream(request, model, provider_module) do
      {:ok, stream} ->
        Logger.debug("Conversation turn_loop: stream started, processing events")
        acc = process_stream(stream, event_handler)
        Logger.debug("Conversation turn_loop: stream complete, handling result")

        handle_turn_result(
          acc,
          session,
          model,
          config,
          event_handler,
          permission_mode,
          project_root,
          provider_module,
          iteration
        )

      {:error, err} ->
        Logger.error("Conversation turn_loop: stream error #{inspect(err)}")
        event_handler.({:error, inspect(err)})
        {:error, err}
    end
  end

  defp do_stream(request, model, nil) do
    Client.stream_message(model, request)
  end

  defp do_stream(request, _model, provider_module) do
    provider_module.stream_message(request)
  end

  defp handle_turn_result(
         acc,
         session,
         model,
         config,
         event_handler,
         permission_mode,
         project_root,
         provider_module,
         iteration
       ) do
    if acc.stream_error do
      Logger.error("Conversation: aborting turn due to stream error: #{inspect(acc.stream_error)}")
      {:error, {:stream_error, acc.stream_error}}
    else
      handle_completed_turn(
        acc,
        session,
        model,
        config,
        event_handler,
        permission_mode,
        project_root,
        provider_module,
        iteration
      )
    end
  end

  defp handle_completed_turn(
         acc,
         session,
         model,
         config,
         event_handler,
         permission_mode,
         project_root,
         provider_module,
         iteration
       ) do
    tool_uses = extract_tool_uses(acc.blocks)
    text_content = extract_text(acc.blocks)

    usage =
      if acc.current_usage do
        Usage.from_api_usage(acc.current_usage)
      else
        %Usage{}
      end

    assistant_blocks =
      Enum.flat_map(acc.blocks, fn
        {_idx, %{type: :text, text: text}} ->
          [{:text, text}]

        {_idx, %{type: :tool_use, id: id, name: name, input: input}} ->
          [{:tool_use, id, name, input}]

        _ ->
          []
      end)

    assistant_msg = %{role: :assistant, blocks: assistant_blocks, usage: usage}
    :ok = Session.add_message(session, assistant_msg)

    if tool_uses == [] do
      Logger.debug("Conversation: turn complete, no tool calls")
      event_handler.({:turn_complete, usage})
      {:ok, %{text: text_content, usage: usage, iterations: iteration + 1}}
    else
      Logger.info("Conversation: executing #{length(tool_uses)} tool(s): #{Enum.map_join(tool_uses, ", ", fn {_id, name, _input} -> name end)}")
      tool_results = execute_tools(tool_uses, permission_mode, event_handler)

      tool_result_blocks =
        Enum.map(tool_results, fn {id, name, output, is_error} ->
          {:tool_result, id, name, output, is_error}
        end)

      tool_msg = %{role: :user, blocks: tool_result_blocks, usage: nil}
      :ok = Session.add_message(session, tool_msg)

      turn_loop(
        session,
        model,
        config,
        event_handler,
        permission_mode,
        project_root,
        provider_module,
        iteration + 1
      )
    end
  end

  defp execute_tools(tool_uses, permission_mode, event_handler) do
    policy =
      Enum.reduce(Registry.builtin_specs(), Permissions.new_policy(permission_mode), fn spec,
                                                                                        pol ->
        Permissions.register_tool(pol, spec.name, spec.permission)
      end)

    Enum.map(tool_uses, fn {id, name, input_json} ->
      event_handler.({:tool_use_start, name, id})

      case Permissions.check(policy, name, input_json) do
        :allow ->
          input = parse_tool_input(input_json)

          case Executor.execute(name, input) do
            {:ok, output} ->
              event_handler.({:tool_result, name, output, false})
              {id, name, output, false}

            {:error, error} ->
              event_handler.({:tool_result, name, error, true})
              {id, name, error, true}
          end

        {:deny, reason} ->
          event_handler.({:tool_result, name, reason, true})
          {id, name, reason, true}
      end
    end)
  end

  defp parse_tool_input(input) when is_binary(input) do
    case Jason.decode(input) do
      {:ok, map} when is_map(map) -> map
      _ -> %{"raw" => input}
    end
  end

  defp parse_tool_input(input) when is_map(input), do: input

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
    parsed =
      case Jason.decode(input) do
        {:ok, map} -> map
        _ -> %{}
      end

    %{type: "tool_use", id: id, name: name, input: parsed}
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
    Logger.debug("Stream event: content_block_start idx=#{idx} type=#{Map.get(block, :type, "?")}")

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
    |> Enum.join("")
  end
end
