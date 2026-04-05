defmodule Viber.API.Usage do
  @moduledoc """
  Token usage counters for an API response.
  """

  @type t :: %__MODULE__{
          input_tokens: non_neg_integer(),
          cache_creation_input_tokens: non_neg_integer(),
          cache_read_input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @enforce_keys [:input_tokens, :output_tokens]
  defstruct [
    :input_tokens,
    :output_tokens,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0
  ]

  @spec total_tokens(t()) :: non_neg_integer()
  def total_tokens(%__MODULE__{input_tokens: i, output_tokens: o}), do: i + o
end

defmodule Viber.API.ToolDefinition do
  @moduledoc """
  A tool definition for the LLM API.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          input_schema: map()
        }

  @enforce_keys [:name, :input_schema]
  defstruct [:name, :description, :input_schema]
end

defimpl Jason.Encoder, for: Viber.API.ToolDefinition do
  def encode(td, opts) do
    td
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> Jason.Encode.map(opts)
  end
end

defmodule Viber.API.InputMessage do
  @moduledoc """
  An input message in a conversation (user or assistant turn).
  """

  @type t :: %__MODULE__{
          role: String.t(),
          content: [map()]
        }

  @enforce_keys [:role, :content]
  defstruct [:role, :content]

  @spec user_text(String.t()) :: t()
  def user_text(text) do
    %__MODULE__{role: "user", content: [%{type: "text", text: text}]}
  end

  @spec user_tool_result(String.t(), String.t(), boolean()) :: t()
  def user_tool_result(tool_use_id, content, is_error) do
    result =
      %{type: "tool_result", tool_use_id: tool_use_id, content: [%{type: "text", text: content}]}

    result = if is_error, do: Map.put(result, :is_error, true), else: result
    %__MODULE__{role: "user", content: [result]}
  end
end

defimpl Jason.Encoder, for: Viber.API.InputMessage do
  def encode(msg, opts) do
    %{role: msg.role, content: msg.content}
    |> Jason.Encode.map(opts)
  end
end

defmodule Viber.API.MessageResponse do
  @moduledoc """
  A complete (non-streaming) response from the LLM API.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          role: String.t(),
          content: [map()],
          model: String.t(),
          stop_reason: String.t() | nil,
          stop_sequence: String.t() | nil,
          usage: Viber.API.Usage.t(),
          request_id: String.t() | nil
        }

  @enforce_keys [:id, :type, :role, :content, :model, :usage]
  defstruct [
    :id,
    :type,
    :role,
    :content,
    :model,
    :stop_reason,
    :stop_sequence,
    :usage,
    :request_id
  ]
end

defmodule Viber.API.MessageRequest do
  @moduledoc """
  A request to the LLM messages API.
  """

  @type t :: %__MODULE__{
          model: String.t(),
          max_tokens: pos_integer(),
          messages: [Viber.API.InputMessage.t()],
          system: String.t() | nil,
          tools: [Viber.API.ToolDefinition.t()] | nil,
          tool_choice: atom() | {:tool, String.t()} | nil,
          stream: boolean()
        }

  @enforce_keys [:model, :max_tokens, :messages]
  defstruct [:model, :max_tokens, :messages, :system, :tools, :tool_choice, stream: false]

  @spec with_streaming(t()) :: t()
  def with_streaming(%__MODULE__{} = req), do: %{req | stream: true}
end

defimpl Jason.Encoder, for: Viber.API.MessageRequest do
  def encode(req, opts) do
    map = %{model: req.model, max_tokens: req.max_tokens, messages: req.messages}

    map = if req.system, do: Map.put(map, :system, req.system), else: map
    map = if req.tools, do: Map.put(map, :tools, req.tools), else: map
    map = if req.stream, do: Map.put(map, :stream, true), else: map

    map =
      if req.tool_choice do
        Map.put(map, :tool_choice, encode_tool_choice(req.tool_choice))
      else
        map
      end

    Jason.Encode.map(map, opts)
  end

  defp encode_tool_choice(:auto), do: %{type: "auto"}
  defp encode_tool_choice(:any), do: %{type: "any"}
  defp encode_tool_choice({:tool, name}), do: %{type: "tool", name: name}
end

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

  @spec decode_usage(map()) :: Viber.API.Usage.t()
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
