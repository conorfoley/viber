defmodule Viber.API.Types do
  @moduledoc """
  Shared type definitions and decode functions for the API layer.
  """

  @type stream_event ::
          {:message_start, Viber.API.MessageResponse.t()}
          | {:content_block_start, non_neg_integer(), map()}
          | {:content_block_delta, non_neg_integer(), map()}
          | {:content_block_stop, non_neg_integer()}
          | {:message_delta, map(), Viber.API.Usage.t()}
          | :message_stop

  @spec decode_response(map()) :: Viber.API.MessageResponse.t()
  def decode_response(json) when is_map(json) do
    %Viber.API.MessageResponse{
      id: json["id"],
      type: json["type"],
      role: json["role"],
      content: Enum.map(json["content"] || [], &decode_output_block/1),
      model: json["model"],
      stop_reason: json["stop_reason"],
      stop_sequence: json["stop_sequence"],
      usage: decode_usage(json["usage"]),
      request_id: json["request_id"]
    }
  end

  @spec decode_stream_event(map()) :: stream_event()
  def decode_stream_event(%{"type" => "message_start", "message" => msg}) do
    {:message_start, decode_response(msg)}
  end

  def decode_stream_event(%{
        "type" => "content_block_start",
        "index" => idx,
        "content_block" => block
      }) do
    {:content_block_start, idx, decode_output_block(block)}
  end

  def decode_stream_event(%{"type" => "content_block_delta", "index" => idx, "delta" => delta}) do
    {:content_block_delta, idx, decode_delta(delta)}
  end

  def decode_stream_event(%{"type" => "content_block_stop", "index" => idx}) do
    {:content_block_stop, idx}
  end

  def decode_stream_event(%{"type" => "message_delta", "delta" => delta, "usage" => usage}) do
    {:message_delta, delta, decode_usage(usage)}
  end

  def decode_stream_event(%{"type" => "message_stop"}) do
    :message_stop
  end

  def decode_stream_event(_unknown), do: nil

  @spec decode_usage(map() | nil) :: Viber.API.Usage.t()
  def decode_usage(nil), do: %Viber.API.Usage{input_tokens: 0, output_tokens: 0}

  def decode_usage(json) when is_map(json) do
    %Viber.API.Usage{
      input_tokens: json["input_tokens"],
      output_tokens: json["output_tokens"],
      cache_creation_input_tokens: json["cache_creation_input_tokens"] || 0,
      cache_read_input_tokens: json["cache_read_input_tokens"] || 0
    }
  end

  defp decode_output_block(%{"type" => "text"} = b) do
    %{type: "text", text: b["text"]}
  end

  defp decode_output_block(%{"type" => "tool_use"} = b) do
    %{type: "tool_use", id: b["id"], name: b["name"], input: b["input"]}
  end

  defp decode_output_block(%{"type" => "thinking"} = b) do
    %{type: "thinking", thinking: b["thinking"] || "", signature: b["signature"]}
  end

  defp decode_output_block(%{"type" => "redacted_thinking"} = b) do
    %{type: "redacted_thinking", data: b["data"]}
  end

  defp decode_delta(%{"type" => "text_delta"} = d) do
    %{type: "text_delta", text: d["text"]}
  end

  defp decode_delta(%{"type" => "input_json_delta"} = d) do
    %{type: "input_json_delta", partial_json: d["partial_json"]}
  end

  defp decode_delta(%{"type" => "thinking_delta"} = d) do
    %{type: "thinking_delta", thinking: d["thinking"]}
  end

  defp decode_delta(%{"type" => "signature_delta"} = d) do
    %{type: "signature_delta", signature: d["signature"]}
  end
end
