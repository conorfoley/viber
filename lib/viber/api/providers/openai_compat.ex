defmodule Viber.API.Providers.OpenAICompat do
  @moduledoc """
  OpenAI-compatible API provider (OpenAI, xAI).
  """

  @behaviour Viber.API.Provider

  alias Viber.API.{Error, MessageRequest, Usage}

  defstruct [:provider_name, :api_key_env, :base_url_env, :default_base_url]

  @type t :: %__MODULE__{
          provider_name: String.t(),
          api_key_env: String.t(),
          base_url_env: String.t(),
          default_base_url: String.t()
        }

  @spec openai() :: t()
  def openai do
    %__MODULE__{
      provider_name: "OpenAI",
      api_key_env: "OPENAI_API_KEY",
      base_url_env: "OPENAI_BASE_URL",
      default_base_url: "https://api.openai.com/v1"
    }
  end

  @spec xai() :: t()
  def xai do
    %__MODULE__{
      provider_name: "xAI",
      api_key_env: "XAI_API_KEY",
      base_url_env: "XAI_BASE_URL",
      default_base_url: "https://api.x.ai/v1"
    }
  end

  @impl true
  def send_message(%MessageRequest{} = request) do
    config = config_for_model(request.model)
    send_message(request, config)
  end

  @spec send_message(MessageRequest.t(), t()) ::
          {:ok, Viber.API.MessageResponse.t()} | {:error, Error.t()}
  def send_message(%MessageRequest{} = request, %__MODULE__{} = config) do
    with {:ok, api_key} <- get_api_key(config),
         req <- build_req(api_key, config),
         body = build_chat_completion_request(request),
         {:ok, %{status: status, body: resp}} when status in 200..299 <-
           Req.post(req, url: chat_completions_path(config), json: body) do
      {:ok, normalize_response(request.model, resp)}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, api_error_from_body(status, body)}

      {:error, %Error{}} = err ->
        err

      {:error, exception} ->
        {:error,
         %Error{
           type: :http,
           message: "http error: #{Exception.message(exception)}",
           retryable: true
         }}
    end
  end

  @impl true
  def stream_message(%MessageRequest{} = request) do
    config = config_for_model(request.model)
    stream_message(request, config)
  end

  @spec stream_message(MessageRequest.t(), t()) :: {:ok, Enumerable.t()} | {:error, Error.t()}
  def stream_message(%MessageRequest{} = request, %__MODULE__{} = config) do
    with {:ok, api_key} <- get_api_key(config),
         req <- build_req(api_key, config),
         body = build_chat_completion_request(%{request | stream: true}),
         {:ok, %{status: status, body: ref}} when status in 200..299 <-
           Req.post(req, url: chat_completions_path(config), json: body, into: :self) do
      {:ok, build_event_stream(ref, request.model)}
    else
      {:ok, %{status: status, body: ref}} ->
        body = collect_async_body(ref)
        {:error, api_error_from_body(status, body)}

      {:error, %Error{}} = err ->
        err

      {:error, exception} ->
        {:error,
         %Error{
           type: :http,
           message: "http error: #{Exception.message(exception)}",
           retryable: true
         }}
    end
  end

  @spec build_chat_completion_request(MessageRequest.t()) :: map()
  def build_chat_completion_request(%MessageRequest{} = request) do
    messages =
      if request.system && request.system != "" do
        [
          %{role: "system", content: request.system}
          | Enum.flat_map(request.messages, &translate_message/1)
        ]
      else
        Enum.flat_map(request.messages, &translate_message/1)
      end

    payload = %{
      model: request.model,
      max_tokens: request.max_tokens,
      messages: messages,
      stream: request.stream
    }

    payload =
      if request.tools do
        Map.put(payload, :tools, Enum.map(request.tools, &openai_tool_definition/1))
      else
        payload
      end

    if request.tool_choice do
      Map.put(payload, :tool_choice, openai_tool_choice(request.tool_choice))
    else
      payload
    end
  end

  @spec normalize_response(String.t(), map()) :: Viber.API.MessageResponse.t()
  def normalize_response(model, %{"choices" => choices} = response) do
    choice = List.first(choices, %{})
    message = choice["message"] || %{}

    content = build_content_blocks(message)

    usage = response["usage"] || %{}

    %Viber.API.MessageResponse{
      id: response["id"],
      type: "message",
      role: message["role"] || "assistant",
      content: content,
      model: non_empty(response["model"]) || model,
      stop_reason: normalize_finish_reason(choice["finish_reason"]),
      stop_sequence: nil,
      usage: %Usage{
        input_tokens: usage["prompt_tokens"] || 0,
        output_tokens: usage["completion_tokens"] || 0,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0
      },
      request_id: nil
    }
  end

  @spec normalize_finish_reason(String.t() | nil) :: String.t() | nil
  def normalize_finish_reason("stop"), do: "end_turn"
  def normalize_finish_reason("tool_calls"), do: "tool_use"
  def normalize_finish_reason(other), do: other

  defp build_content_blocks(message) do
    text_blocks =
      case message["content"] do
        nil -> []
        "" -> []
        text -> [%{type: "text", text: text}]
      end

    tool_blocks =
      (message["tool_calls"] || [])
      |> Enum.map(fn tc ->
        %{
          type: "tool_use",
          id: tc["id"],
          name: get_in(tc, ["function", "name"]),
          input: parse_tool_arguments(get_in(tc, ["function", "arguments"]) || "{}")
        }
      end)

    text_blocks ++ tool_blocks
  end

  defp translate_message(%Viber.API.InputMessage{role: "assistant", content: content}) do
    {text, rev_tool_calls} =
      Enum.reduce(content, {"", []}, fn block, {txt, tcs} ->
        case block do
          %{type: "text", text: t} ->
            {txt <> t, tcs}

          %{type: "tool_use", id: id, name: name, input: input} ->
            tc = %{
              id: id,
              type: "function",
              function: %{name: name, arguments: Jason.encode!(input)}
            }

            {txt, [tc | tcs]}

          _ ->
            {txt, tcs}
        end
      end)

    tool_calls = Enum.reverse(rev_tool_calls)

    if text == "" && tool_calls == [] do
      []
    else
      msg = %{role: "assistant"}
      msg = if text != "", do: Map.put(msg, :content, text), else: msg
      msg = if tool_calls != [], do: Map.put(msg, :tool_calls, tool_calls), else: msg
      [msg]
    end
  end

  defp translate_message(%Viber.API.InputMessage{content: content}) do
    Enum.flat_map(content, fn
      %{type: "text", text: text} ->
        [%{role: "user", content: text}]

      %{type: "tool_result", tool_use_id: tool_use_id, content: tc_content} = block ->
        text =
          tc_content
          |> Enum.map(fn
            %{type: "text", text: t} -> t
            %{type: "json", value: v} -> Jason.encode!(v)
            _ -> ""
          end)
          |> Enum.join("\n")

        msg = %{role: "tool", tool_call_id: tool_use_id, content: text}
        msg = if Map.get(block, :is_error, false), do: Map.put(msg, :is_error, true), else: msg
        [msg]

      _ ->
        []
    end)
  end

  defp openai_tool_definition(%Viber.API.ToolDefinition{} = td) do
    func = %{name: td.name, parameters: td.input_schema}
    func = if td.description, do: Map.put(func, :description, td.description), else: func
    %{type: "function", function: func}
  end

  defp openai_tool_choice(:auto), do: "auto"
  defp openai_tool_choice(:any), do: "required"
  defp openai_tool_choice({:tool, name}), do: %{type: "function", function: %{name: name}}

  defp parse_tool_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      _ -> %{"raw" => args}
    end
  end

  defp parse_tool_arguments(args), do: args

  defp non_empty(""), do: nil
  defp non_empty(nil), do: nil
  defp non_empty(s), do: s

  defp config_for_model(model) do
    cond do
      String.starts_with?(model, "grok") -> xai()
      true -> openai()
    end
  end

  defp get_api_key(%__MODULE__{} = config) do
    case System.get_env(config.api_key_env) do
      nil -> {:error, Error.missing_credentials(config.provider_name, [config.api_key_env])}
      "" -> {:error, Error.missing_credentials(config.provider_name, [config.api_key_env])}
      key -> {:ok, key}
    end
  end

  defp build_req(api_key, %__MODULE__{} = config) do
    base_url = System.get_env(config.base_url_env) || config.default_base_url

    Req.new(
      base_url: base_url,
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]
    )
  end

  defp chat_completions_path(%__MODULE__{} = config) do
    base_url = System.get_env(config.base_url_env) || config.default_base_url
    trimmed = String.trim_trailing(base_url, "/")

    if String.ends_with?(trimmed, "/chat/completions") do
      ""
    else
      "/chat/completions"
    end
  end

  defp build_event_stream(ref, model) do
    Stream.resource(
      fn -> {ref, "", stream_state_new(model)} end,
      fn
        :done ->
          {:halt, :done}

        {ref, buffer, state} ->
          receive do
            {^ref, {:data, chunk}} ->
              {events, new_buffer, new_state} = process_openai_chunk(buffer <> chunk, state)
              {events, {ref, new_buffer, new_state}}

            {^ref, :done} ->
              events = stream_state_finish(state)
              {events, :done}
          end
      end,
      fn _ -> :ok end
    )
  end

  defp process_openai_chunk(buffer, state) do
    {rev_events, new_buffer, new_state} = process_openai_frames(buffer, state, [])
    {Enum.reverse(rev_events), new_buffer, new_state}
  end

  defp process_openai_frames(buffer, state, rev_acc) do
    case next_sse_frame(buffer) do
      {frame, rest} ->
        case parse_openai_frame(frame) do
          {:ok, nil} ->
            process_openai_frames(rest, state, rev_acc)

          {:ok, chunk} ->
            {events, new_state} = stream_state_ingest(state, chunk)
            process_openai_frames(rest, new_state, Enum.reverse(events) ++ rev_acc)
        end

      nil ->
        {rev_acc, buffer, state}
    end
  end

  defp next_sse_frame(buffer) do
    case :binary.match(buffer, "\n\n") do
      {pos, _} ->
        frame = binary_part(buffer, 0, pos)
        rest = binary_part(buffer, pos + 2, byte_size(buffer) - pos - 2)
        {frame, rest}

      :nomatch ->
        case :binary.match(buffer, "\r\n\r\n") do
          {pos, _} ->
            frame = binary_part(buffer, 0, pos)
            rest = binary_part(buffer, pos + 4, byte_size(buffer) - pos - 4)
            {frame, rest}

          :nomatch ->
            nil
        end
    end
  end

  defp parse_openai_frame(frame) do
    trimmed = String.trim(frame)

    if trimmed == "" do
      {:ok, nil}
    else
      data_lines =
        trimmed
        |> String.split("\n")
        |> Enum.flat_map(fn line ->
          cond do
            String.starts_with?(line, ":") ->
              []

            String.starts_with?(line, "data:") ->
              [String.trim_leading(String.trim_leading(line, "data:"), " ")]

            true ->
              []
          end
        end)

      if data_lines == [] do
        {:ok, nil}
      else
        payload = Enum.join(data_lines, "\n")

        if payload == "[DONE]" do
          {:ok, nil}
        else
          case Jason.decode(payload) do
            {:ok, chunk} -> {:ok, chunk}
            {:error, _} -> {:ok, nil}
          end
        end
      end
    end
  end

  defmodule StreamState do
    @moduledoc false

    defstruct model: nil,
              message_started: false,
              text_started: false,
              text_finished: false,
              finished: false,
              stop_reason: nil,
              usage: nil,
              tool_calls: %{}
  end

  defp stream_state_new(model) do
    %StreamState{model: model}
  end

  @spec stream_events_from_chunks(String.t(), [map()]) :: [term()]
  def stream_events_from_chunks(model, chunks) do
    {events, state} =
      Enum.reduce(chunks, {[], stream_state_new(model)}, fn chunk, {acc, st} ->
        {new_events, new_state} = stream_state_ingest(st, chunk)
        {acc ++ new_events, new_state}
      end)

    events ++ stream_state_finish(state)
  end

  defp stream_state_ingest(%StreamState{} = state, chunk) do
    rev_events = []

    {rev_events, state} =
      if not state.message_started do
        event =
          {:message_start,
           %Viber.API.MessageResponse{
             id: chunk["id"],
             type: "message",
             role: "assistant",
             content: [],
             model: (chunk["model"] || state.model) |> non_empty() || state.model,
             usage: %Usage{input_tokens: 0, output_tokens: 0}
           }}

        {[event | rev_events], %{state | message_started: true}}
      else
        {rev_events, state}
      end

    state =
      case chunk["usage"] do
        %{"prompt_tokens" => pt, "completion_tokens" => ct} ->
          %{state | usage: %Usage{input_tokens: pt, output_tokens: ct}}

        _ ->
          state
      end

    choices = chunk["choices"] || []

    {rev_events, state} =
      Enum.reduce(choices, {rev_events, state}, fn choice, {evts, st} ->
        delta = choice["delta"] || %{}

        {evts, st} =
          case delta["content"] do
            nil ->
              {evts, st}

            "" ->
              {evts, st}

            text ->
              if not st.text_started do
                delta_event = {:content_block_delta, 0, %{type: "text_delta", text: text}}
                start_event = {:content_block_start, 0, %{type: "text", text: ""}}
                {[delta_event, start_event | evts], %{st | text_started: true}}
              else
                delta_event = {:content_block_delta, 0, %{type: "text_delta", text: text}}
                {[delta_event | evts], st}
              end
          end

        tool_calls = delta["tool_calls"] || []

        {evts, st} =
          Enum.reduce(tool_calls, {evts, st}, fn tc, {e, s} ->
            idx = tc["index"] || 0

            existing =
              Map.get(s.tool_calls, idx, %{
                id: nil,
                name: nil,
                arguments: "",
                started: false,
                stopped: false
              })

            argument_delta = get_in(tc, ["function", "arguments"])

            existing =
              existing
              |> then(fn ex -> if tc["id"], do: %{ex | id: tc["id"]}, else: ex end)
              |> then(fn ex ->
                case get_in(tc, ["function", "name"]) do
                  nil -> ex
                  name -> %{ex | name: name}
                end
              end)
              |> then(fn ex ->
                case argument_delta do
                  nil -> ex
                  args -> %{ex | arguments: ex.arguments <> args}
                end
              end)

            block_index = idx + 1

            {e, existing} =
              if not existing.started and existing.name do
                start =
                  {:content_block_start, block_index,
                   %{
                     type: "tool_use",
                     id: existing.id || "tool_call_#{idx}",
                     name: existing.name,
                     input: %{}
                   }}

                {[start | e], %{existing | started: true}}
              else
                {e, existing}
              end

            e =
              if existing.started and is_binary(argument_delta) and argument_delta != "" do
                delta_event =
                  {:content_block_delta, block_index,
                   %{type: "input_json_delta", partial_json: argument_delta}}

                [delta_event | e]
              else
                e
              end

            s = %{s | tool_calls: Map.put(s.tool_calls, idx, existing)}
            {e, s}
          end)

        st =
          case choice["finish_reason"] do
            nil -> st
            reason -> %{st | stop_reason: normalize_finish_reason(reason)}
          end

        {evts, st}
      end)

    {Enum.reverse(rev_events), state}
  end

  defp stream_state_finish(%StreamState{} = state) do
    if state.finished or not state.message_started do
      []
    else
      rev_events = []

      rev_events =
        if state.text_started and not state.text_finished do
          [{:content_block_stop, 0} | rev_events]
        else
          rev_events
        end

      rev_events =
        Enum.reduce(state.tool_calls, rev_events, fn {idx, tc}, evts ->
          block_index = idx + 1

          evts =
            if not tc.started and tc.name do
              start =
                {:content_block_start, block_index,
                 %{type: "tool_use", id: tc.id || "tool_call_#{idx}", name: tc.name, input: %{}}}

              [start | evts]
            else
              evts
            end

          if (tc.started or tc.name) and not tc.stopped do
            [{:content_block_stop, block_index} | evts]
          else
            evts
          end
        end)

      usage = state.usage || %Usage{input_tokens: 0, output_tokens: 0}

      Enum.reverse(rev_events) ++
        [
          {:message_delta,
           %{"stop_reason" => state.stop_reason || "end_turn", "stop_sequence" => nil}, usage},
          :message_stop
        ]
    end
  end

  defp collect_async_body(ref) when is_reference(ref) do
    do_collect_async_body(ref, [])
  end

  defp collect_async_body(body), do: body

  defp do_collect_async_body(ref, acc) do
    receive do
      {^ref, {:data, data}} -> do_collect_async_body(ref, [data | acc])
      {^ref, :done} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
    after
      5_000 -> acc |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end

  defp api_error_from_body(status, body) when is_map(body) do
    message =
      case body do
        %{"error" => %{"message" => msg}} -> msg
        other -> inspect(other)
      end

    Error.api_error(status, message, retryable_status?(status))
  end

  defp api_error_from_body(status, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> api_error_from_body(status, map)
      _ -> Error.api_error(status, body, retryable_status?(status))
    end
  end

  defp api_error_from_body(status, body) do
    Error.api_error(status, inspect(body), retryable_status?(status))
  end

  defp retryable_status?(status) when status in [408, 409, 429, 500, 502, 503, 504], do: true
  defp retryable_status?(_), do: false
end
