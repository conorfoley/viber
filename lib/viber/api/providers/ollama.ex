defmodule Viber.API.Providers.Ollama do
  @moduledoc """
  Native Ollama provider built on `/api/chat`.

  Ollama's OpenAI-compatible endpoint ignores per-request options, so a
  long system prompt plus tool schemas can overflow the model's default
  context window. When that happens Ollama silently drops the oldest
  messages. This provider uses the native API instead, so it can set
  `options.num_ctx` on each request. Streamed NDJSON chunks are converted
  to OpenAI-shaped deltas and run through `OpenAIStreamState`, so they
  produce the same events as the other providers.
  """

  @behaviour Viber.API.Provider

  alias Viber.API.{Error, MessageRequest, MessageResponse, Usage}
  alias Viber.API.Providers.{OpenAICompat, OpenAIStreamState}

  @default_base_url "http://localhost:11434"
  @default_num_ctx 32_768
  @stream_timeout 300_000

  @doc "The context window requested when `ollamaNumCtx` is not configured."
  @spec default_num_ctx() :: pos_integer()
  def default_num_ctx, do: @default_num_ctx

  @spec list_models(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def list_models(opts \\ []) do
    url = api_url(Keyword.get(opts, :base_url), "/api/tags")

    request_fun =
      Keyword.get(opts, :request_fun, fn request_url, request_opts ->
        Req.get(request_url, request_opts)
      end)

    case request_fun.(url, receive_timeout: 1_500) do
      {:ok, %{status: status, body: %{"models" => models}}} when status in 200..299 ->
        names =
          models
          |> Enum.map(&Map.get(&1, "name"))
          |> Enum.filter(&is_binary/1)

        {:ok, names}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def send_message(%MessageRequest{} = request) do
    body = build_chat_request(%{request | stream: false})

    case Req.post(build_req(request), url: "/api/chat", json: body) do
      {:ok, %{status: status, body: resp}} when status in 200..299 and is_map(resp) ->
        {:ok, normalize_response(body.model, resp)}

      {:ok, %{status: status, body: resp}} ->
        {:error, api_error(status, resp, body)}

      {:error, exception} ->
        {:error, http_error(exception)}
    end
  end

  @impl true
  def stream_message(%MessageRequest{} = request) do
    body = build_chat_request(%{request | stream: true})

    case Req.post(build_req(request), url: "/api/chat", json: body, into: :self) do
      {:ok, %{status: status, body: async}} when status in 200..299 ->
        {:ok, build_event_stream(async, body)}

      {:ok, %{status: status, body: async}} ->
        {:error, api_error(status, collect_async_body(async), body)}

      {:error, exception} ->
        {:error, http_error(exception)}
    end
  end

  @doc """
  Builds the native `/api/chat` payload for a request.
  """
  @spec build_chat_request(MessageRequest.t()) :: map()
  def build_chat_request(%MessageRequest{} = request) do
    openai =
      OpenAICompat.build_chat_completion_request(%{
        request
        | model: strip_prefix(request.model),
          system: system_text(request.system)
      })

    options =
      %{num_ctx: num_ctx(request)}
      |> maybe_put(:num_predict, positive(request.max_tokens))

    %{
      model: openai.model,
      messages: native_messages(openai.messages),
      stream: request.stream,
      options: options
    }
    |> maybe_put(:tools, openai[:tools])
  end

  @doc """
  Translates native `/api/chat` stream chunks into provider stream events.
  """
  @spec stream_events_from_chunks(String.t(), [map()], keyword()) :: [term()]
  def stream_events_from_chunks(model, chunks, opts \\ []) do
    num_ctx = Keyword.get(opts, :num_ctx, @default_num_ctx)

    {events, state} =
      Enum.reduce(chunks, {[], new_stream_state(model, num_ctx)}, fn chunk, {acc, st} ->
        {new_events, st} = ingest_chunk(st, chunk)
        {acc ++ new_events, st}
      end)

    events ++ OpenAIStreamState.finish(state.inner)
  end

  defp native_messages(messages) do
    {rev, _names} =
      Enum.reduce(messages, {[], %{}}, fn message, {acc, names} ->
        {native, names} = native_message(message, names)
        {[native | acc], names}
      end)

    Enum.reverse(rev)
  end

  defp native_message(%{role: "assistant", tool_calls: calls} = message, names) do
    native_calls =
      Enum.map(calls, fn %{id: id, function: %{name: name, arguments: args}} ->
        %{id: id, function: %{name: name, arguments: decode_arguments(args)}}
      end)

    names =
      Enum.reduce(calls, names, fn call, acc -> Map.put(acc, call.id, call.function.name) end)

    native =
      message
      |> Map.put(:tool_calls, native_calls)
      |> Map.put_new(:content, "")

    {native, names}
  end

  defp native_message(%{role: "tool", tool_call_id: id} = message, names) do
    native =
      message
      |> Map.delete(:is_error)
      |> maybe_put(:tool_name, Map.get(names, id))

    {native, names}
  end

  defp native_message(message, names), do: {message, names}

  defp decode_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp decode_arguments(args) when is_map(args), do: args
  defp decode_arguments(_args), do: %{}

  defp normalize_response(model, resp) do
    message = resp["message"] || %{}
    text_blocks = text_blocks(message["content"])
    tool_blocks = tool_blocks(message["tool_calls"] || [])

    %MessageResponse{
      id: nil,
      type: "message",
      role: "assistant",
      content: text_blocks ++ tool_blocks,
      model: resp["model"] || model,
      stop_reason: stop_reason(resp["done_reason"], tool_blocks != []),
      stop_sequence: nil,
      usage: %Usage{
        input_tokens: resp["prompt_eval_count"] || 0,
        output_tokens: resp["eval_count"] || 0,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0
      },
      request_id: nil
    }
  end

  defp text_blocks(text) when is_binary(text) and text != "", do: [%{type: "text", text: text}]
  defp text_blocks(_text), do: []

  defp tool_blocks(calls) do
    calls
    |> Enum.with_index()
    |> Enum.map(fn {call, index} ->
      %{
        type: "tool_use",
        id: call["id"] || "call_#{index}",
        name: get_in(call, ["function", "name"]),
        input: decode_arguments(get_in(call, ["function", "arguments"]))
      }
    end)
  end

  defp stop_reason(_reason, true), do: "tool_use"
  defp stop_reason("length", false), do: "max_tokens"
  defp stop_reason(_reason, false), do: "end_turn"

  defp new_stream_state(model, num_ctx) do
    %{inner: OpenAIStreamState.new(model), tool_index: 0, saw_tools: false, num_ctx: num_ctx}
  end

  defp ingest_chunk(state, %{"error" => message}) do
    {[{:stream_error, context_hint(to_string(message), state.num_ctx)}], state}
  end

  defp ingest_chunk(state, chunk) do
    message = chunk["message"] || %{}
    calls = message["tool_calls"] || []

    tool_deltas =
      calls
      |> Enum.with_index(state.tool_index)
      |> Enum.map(fn {call, index} ->
        %{
          "index" => index,
          "id" => call["id"] || "call_#{index}",
          "function" => %{
            "name" => get_in(call, ["function", "name"]),
            "arguments" =>
              Jason.encode!(decode_arguments(get_in(call, ["function", "arguments"])))
          }
        }
      end)

    state = %{
      state
      | tool_index: state.tool_index + length(calls),
        saw_tools: state.saw_tools or calls != []
    }

    delta =
      %{}
      |> maybe_put("content", message["content"])
      |> maybe_put("tool_calls", if(tool_deltas == [], do: nil, else: tool_deltas))

    openai_chunk =
      %{"model" => chunk["model"], "choices" => [%{"delta" => delta, "finish_reason" => nil}]}
      |> finalize_chunk(chunk, state)

    {events, inner} = OpenAIStreamState.ingest(state.inner, openai_chunk)
    {events, %{state | inner: inner}}
  end

  defp finalize_chunk(openai_chunk, %{"done" => true} = chunk, state) do
    finish =
      cond do
        state.saw_tools -> "tool_calls"
        chunk["done_reason"] == "length" -> "max_tokens"
        true -> "stop"
      end

    openai_chunk
    |> put_in(["choices", Access.at(0), "finish_reason"], finish)
    |> Map.put("usage", %{
      "prompt_tokens" => chunk["prompt_eval_count"] || 0,
      "completion_tokens" => chunk["eval_count"] || 0
    })
  end

  defp finalize_chunk(openai_chunk, _chunk, _state), do: openai_chunk

  defp build_event_stream(%Req.Response.Async{} = async, body) do
    num_ctx = body.options.num_ctx

    Stream.resource(
      fn -> {async, "", new_stream_state(body.model, num_ctx)} end,
      fn
        :done ->
          {:halt, :done}

        {async, buffer, state} ->
          ref = async.ref

          receive do
            {^ref, _} = message ->
              handle_async_message(async.stream_fun.(ref, message), async, buffer, state)
          after
            @stream_timeout -> {[{:stream_error, :timeout}], :done}
          end
      end,
      fn
        {async, _buffer, _state} -> Req.cancel_async_response(async)
        :done -> :ok
      end
    )
  end

  defp handle_async_message({:ok, [data: data]}, async, buffer, state) do
    {events, buffer, state} = process_lines(buffer <> data, state)
    {events, {async, buffer, state}}
  end

  defp handle_async_message({:ok, [:done]}, _async, buffer, state) do
    {events, _buffer, state} = process_lines(buffer <> "\n", state)
    {events ++ OpenAIStreamState.finish(state.inner), :done}
  end

  defp handle_async_message({:ok, _other}, async, buffer, state) do
    {[], {async, buffer, state}}
  end

  defp handle_async_message({:error, reason}, _async, _buffer, _state) do
    {[{:stream_error, reason}], :done}
  end

  defp process_lines(buffer, state) do
    {lines, [rest]} = buffer |> String.split("\n") |> Enum.split(-1)

    {rev_events, state} =
      lines
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce({[], state}, fn line, {acc, st} ->
        case Jason.decode(line) do
          {:ok, chunk} when is_map(chunk) ->
            {events, st} = ingest_chunk(st, chunk)
            {Enum.reverse(events) ++ acc, st}

          _ ->
            {acc, st}
        end
      end)

    {Enum.reverse(rev_events), rest, state}
  end

  defp collect_async_body(%Req.Response.Async{} = async), do: collect_async_body(async, [])
  defp collect_async_body(body), do: body

  defp collect_async_body(async, acc) do
    ref = async.ref

    receive do
      {^ref, _} = message ->
        case async.stream_fun.(ref, message) do
          {:ok, [data: data]} -> collect_async_body(async, [data | acc])
          {:ok, [:done]} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
          {:ok, _other} -> collect_async_body(async, acc)
          {:error, _reason} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
        end
    after
      5_000 -> acc |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end

  defp api_error(status, body, request_body) do
    message =
      case decode_body(body) do
        %{"error" => %{"message" => msg}} -> msg
        %{"error" => msg} when is_binary(msg) -> msg
        other when is_binary(other) -> other
        other -> inspect(other)
      end

    case context_hint(message, request_body.options.num_ctx) do
      ^message -> Error.api_error(status, message, status in [408, 429, 500, 502, 503, 504])
      hint -> Error.api_error(status, hint, false)
    end
  end

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> body
    end
  end

  defp decode_body(body), do: body

  @doc """
  Rewrites Ollama's "no user query found" error, which it returns when the
  prompt overflowed the context window and the user message was truncated
  away, into an actionable message. Other messages are returned unchanged.
  """
  @spec context_hint(String.t(), pos_integer()) :: String.t()
  def context_hint(message, num_ctx) do
    if String.contains?(String.downcase(message), "no user query found") do
      "Ollama dropped your message because the prompt exceeds the model's context window " <>
        "(num_ctx=#{num_ctx}). Raise \"ollamaNumCtx\" in .viber/settings.json " <>
        "(Ollama said: #{message})"
    else
      message
    end
  end

  defp http_error(exception) do
    %Error{
      type: :http,
      message: "http error: #{Exception.message(exception)}",
      retryable: true
    }
  end

  defp build_req(%MessageRequest{} = request) do
    overrides = request.provider_overrides || %{}
    api_key = Map.get(overrides, :api_key) || System.get_env("OLLAMA_API_KEY")

    headers =
      if is_binary(api_key) and api_key != "",
        do: [{"authorization", "Bearer #{api_key}"}],
        else: []

    Req.new(
      base_url: api_url(Map.get(overrides, :base_url), ""),
      headers: headers,
      receive_timeout: @stream_timeout,
      retry: false
    )
  end

  defp api_url(base_url, path) do
    base =
      (non_empty(base_url) || non_empty(System.get_env("OLLAMA_HOST")) || @default_base_url)
      |> String.trim()
      |> String.trim_trailing("/")
      |> String.replace_suffix("/v1", "")
      |> ensure_scheme()

    base <> path
  end

  defp ensure_scheme("http://" <> _ = url), do: url
  defp ensure_scheme("https://" <> _ = url), do: url
  defp ensure_scheme(url), do: "http://" <> url

  defp num_ctx(%MessageRequest{provider_overrides: overrides}) when is_map(overrides) do
    positive(Map.get(overrides, :num_ctx)) || @default_num_ctx
  end

  defp num_ctx(_request), do: @default_num_ctx

  defp system_text(blocks) when is_list(blocks) do
    Enum.map_join(blocks, "\n\n", fn
      %{text: text} -> text
      %{"text" => text} -> text
      _ -> ""
    end)
  end

  defp system_text(system), do: system

  defp strip_prefix("ollama:" <> model), do: model
  defp strip_prefix(model), do: model

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil

  defp non_empty(value) when is_binary(value) and value != "", do: value
  defp non_empty(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
