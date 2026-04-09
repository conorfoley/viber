defmodule Viber.API.Providers.Anthropic do
  @moduledoc """
  Anthropic (Claude) API provider.
  """

  require Logger

  @behaviour Viber.API.Provider

  alias Viber.API.{Error, MessageRequest, SSEParser, Types}

  @anthropic_version "2023-06-01"

  @impl true
  def send_message(%MessageRequest{} = request) do
    Logger.debug("Anthropic send_message: model=#{request.model}")

    with {:ok, api_key} <- get_api_key() do
      req = build_req(api_key)
      Logger.debug("Anthropic send_message: posting to /v1/messages")

      case Req.post(req, url: "/v1/messages", json: %{request | stream: false}) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          Logger.debug("Anthropic send_message: success status=#{status}")
          {:ok, Types.decode_response(body)}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Anthropic send_message: API error status=#{status}")
          {:error, api_error_from_body(status, body)}

        {:error, exception} ->
          Logger.error("Anthropic send_message: HTTP error #{Exception.message(exception)}")

          {:error,
           %Error{
             type: :http,
             message: "http error: #{Exception.message(exception)}",
             retryable: true
           }}
      end
    end
  end

  @impl true
  def stream_message(%MessageRequest{} = request) do
    Logger.debug("Anthropic stream_message: model=#{request.model}")

    with {:ok, api_key} <- get_api_key() do
      req = build_req(api_key)
      Logger.debug("Anthropic stream_message: posting to /v1/messages (streaming)")

      case Req.post(req,
             url: "/v1/messages",
             json: MessageRequest.with_streaming(request),
             into: :self
           ) do
        {:ok, %{status: status, headers: headers, body: async}} when status in 200..299 ->
          content_type = get_header(headers, "content-type")

          if content_type && not String.contains?(content_type, "text/event-stream") do
            Logger.warning(
              "Anthropic stream_message: unexpected content-type #{content_type}, expected text/event-stream"
            )
          end

          Logger.debug("Anthropic stream_message: stream started, status=#{status}")
          {:ok, build_event_stream(async)}

        {:ok, %{status: status, body: async}} ->
          Logger.warning("Anthropic stream_message: API error status=#{status}")
          body = collect_async_body(async)
          {:error, api_error_from_body(status, body)}

        {:error, exception} ->
          Logger.error("Anthropic stream_message: HTTP error #{Exception.message(exception)}")

          {:error,
           %Error{
             type: :http,
             message: "http error: #{Exception.message(exception)}",
             retryable: true
           }}
      end
    end
  end

  defp get_api_key do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil ->
        Logger.warning("ANTHROPIC_API_KEY not set in environment")
        {:error, Error.missing_credentials("Anthropic", ["ANTHROPIC_API_KEY"])}

      "" ->
        Logger.warning("ANTHROPIC_API_KEY is set but empty")
        {:error, Error.missing_credentials("Anthropic", ["ANTHROPIC_API_KEY"])}

      key ->
        Logger.debug(
          "ANTHROPIC_API_KEY found (#{String.length(key)} chars, ends in ...#{String.slice(key, -4..-1//1)})"
        )

        {:ok, key}
    end
  end

  defp build_req(api_key) do
    base_url = System.get_env("ANTHROPIC_BASE_URL") || "https://api.anthropic.com"

    Req.new(
      base_url: base_url,
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", @anthropic_version},
        {"content-type", "application/json"}
      ],
      # Disable compression to prevent SSE chunks from being buffered
      # by gzip/br encoding, which stalls streaming indefinitely
      compressed: false,
      # Force HTTP/1.1 to avoid HTTP/2 multiplexing issues with into: :self
      connect_options: [protocols: [:http1]],
      # Allow up to 5 minutes between TCP segments for large streaming payloads
      receive_timeout: 300_000
    )
  end

  defp build_event_stream(%Req.Response.Async{} = async) do
    Logger.debug("Anthropic SSE: stream resource initialized, consuming async body")

    Stream.resource(
      fn -> {async, SSEParser.new(), 0} end,
      fn
        :done ->
          {:halt, :done}

        {async, parser, chunk_count} ->
          ref = async.ref

          receive do
            {^ref, _} = message ->
              case async.stream_fun.(ref, message) do
                {:ok, [data: chunk]} ->
                  new_count = chunk_count + 1

                  if new_count == 1,
                    do:
                      Logger.debug(
                        "Anthropic SSE: first chunk received (#{byte_size(chunk)} bytes)"
                      )

                  if rem(new_count, 50) == 0,
                    do: Logger.debug("Anthropic SSE: #{new_count} chunks received")

                  case SSEParser.push(parser, chunk) do
                    {:ok, new_parser, events} -> {events, {async, new_parser, new_count}}
                    {:error, _} = err -> {[err], {async, parser, new_count}}
                  end

                {:ok, [:done]} ->
                  Logger.debug("Anthropic SSE: stream done after #{chunk_count} chunks")

                  case SSEParser.finish(parser) do
                    {:ok, events} -> {events, :done}
                    {:error, _} = err -> {[err], :done}
                  end

                {:ok, [trailers: _]} ->
                  {[], {async, parser, chunk_count}}

                {:error, e} ->
                  Logger.error("Anthropic SSE: stream error #{inspect(e)}")
                  {[{:stream_error, e}], :done}
              end

            other ->
              Logger.warning("Anthropic SSE: unexpected message: #{inspect(other)}")
              {[], {async, parser, chunk_count}}
          after
            60_000 ->
              Logger.warning(
                "Anthropic SSE: no data received for 60s, may be stalled (#{chunk_count} chunks so far)"
              )

              {[], {async, parser, chunk_count}}
          end
      end,
      fn _ -> :ok end
    )
  end

  defp collect_async_body(%Req.Response.Async{} = async) do
    Enum.join(async)
  end

  defp collect_async_body(body) when is_binary(body), do: body
  defp collect_async_body(body), do: inspect(body)

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

  defp get_header(headers, name) when is_map(headers) do
    case Map.get(headers, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp get_header(headers, name) when is_list(headers) do
    case List.keyfind(headers, name, 0) do
      {_, value} -> value
      nil -> nil
    end
  end
end
