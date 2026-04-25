defmodule Viber.Runtime.Event do
  @moduledoc """
  Canonical event emitted by `Viber.Runtime.Conversation` and consumed by every
  frontend (CLI renderer, HTTP/SSE, Discord gateway, future TUI/browser apps).

  An event is a typed struct with a `type` atom and a `payload` map. All
  payload keys are atoms at rest; `to_map/1` renders the full event into a
  stable, versioned JSON-friendly map for wire transport.

  ## Event types and payload schemas

  * `:text_delta` — `%{text: String.t()}`
  * `:thinking_delta` — `%{text: String.t()}`
  * `:tool_use_start` — `%{name: String.t(), id: String.t()}`
  * `:tool_result` — `%{name: String.t(), id: String.t() | nil, output: String.t(), is_error: boolean()}`
  * `:turn_complete` — `%{usage: usage_map()}`
  * `:error` — `%{message: String.t()}`
  * `:interrupted` — `%{message: String.t()}`
  * `:permission_request` — `%{request_id: String.t(), tool: String.t(), input: String.t()}` (reserved for M2)
  * `:permission_decision` — `%{request_id: String.t(), decision: :allow | :deny | :always_allow}` (reserved for M2)
  * `:message_added` — `%{role: String.t()}` (reserved for M4)
  * `:usage_updated` — `%{usage: usage_map()}` (reserved for M4)

  `usage_map()` is the map produced by `Viber.Runtime.Usage` flattened to
  `%{input_tokens, output_tokens, cache_creation_tokens, cache_read_tokens, turns, total_tokens}`.

  ## Wire protocol (`to_map/1`)

      %{
        "v" => 1,
        "type" => "text_delta",
        "payload" => %{"text" => "hello"},
        "session_id" => "abc" | nil,
        "seq" => 42 | nil,
        "timestamp" => "2026-04-16T21:00:00.000Z" | nil
      }
  """

  alias Viber.Runtime.Usage

  @wire_version 1

  @known_types ~w(text_delta thinking_delta tool_use_start tool_result turn_complete error interrupted permission_request permission_decision message_added usage_updated model_changed session_cleared command_result info)

  @type type ::
          :text_delta
          | :thinking_delta
          | :tool_use_start
          | :tool_result
          | :turn_complete
          | :error
          | :interrupted
          | :permission_request
          | :permission_decision
          | :message_added
          | :usage_updated
          | :model_changed
          | :session_cleared
          | :command_result
          | :info

  @type t :: %__MODULE__{
          type: type(),
          payload: map(),
          session_id: String.t() | nil,
          seq: non_neg_integer() | nil,
          timestamp: DateTime.t() | nil
        }

  @enforce_keys [:type, :payload]
  defstruct type: nil,
            payload: %{},
            session_id: nil,
            seq: nil,
            timestamp: nil

  @spec new(type(), map(), keyword()) :: t()
  def new(type, payload, opts \\ []) when is_atom(type) and is_map(payload) do
    %__MODULE__{
      type: type,
      payload: payload,
      session_id: Keyword.get(opts, :session_id),
      seq: Keyword.get(opts, :seq),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now())
    }
  end

  @spec wire_version() :: pos_integer()
  def wire_version, do: @wire_version

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "v" => @wire_version,
      "type" => Atom.to_string(event.type),
      "payload" => payload_to_wire(event.payload),
      "session_id" => event.session_id,
      "seq" => event.seq,
      "timestamp" => encode_timestamp(event.timestamp)
    }
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"type" => type_str, "payload" => payload} = map) when is_map(payload) do
    with {:ok, type} <- parse_type(type_str) do
      {:ok,
       %__MODULE__{
         type: type,
         payload: atomize_payload(payload),
         session_id: Map.get(map, "session_id"),
         seq: Map.get(map, "seq"),
         timestamp: decode_timestamp(Map.get(map, "timestamp"))
       }}
    end
  end

  def from_map(_), do: {:error, :invalid_event}

  @spec usage_to_map(Usage.t()) :: map()
  def usage_to_map(%Usage{} = usage) do
    %{
      input_tokens: usage.input_tokens,
      output_tokens: usage.output_tokens,
      cache_creation_tokens: usage.cache_creation_tokens,
      cache_read_tokens: usage.cache_read_tokens,
      turns: usage.turns,
      total_tokens: Usage.total_tokens(usage)
    }
  end

  defp payload_to_wire(payload) do
    Map.new(payload, fn {k, v} -> {to_string(k), wire_value(v)} end)
  end

  defp wire_value(%Usage{} = u), do: Map.new(usage_to_map(u), fn {k, v} -> {to_string(k), v} end)
  defp wire_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp wire_value(v) when is_map(v) and not is_struct(v), do: payload_to_wire(v)

  defp wire_value(v) when is_atom(v) and not is_boolean(v) and not is_nil(v),
    do: Atom.to_string(v)

  defp wire_value(v), do: v

  defp atomize_payload(map) do
    Map.new(map, fn {k, v} -> {safe_atom(k), v} end)
  end

  defp safe_atom(k) when is_atom(k), do: k

  defp safe_atom(k) when is_binary(k) do
    String.to_existing_atom(k)
  rescue
    ArgumentError -> k
  end

  defp encode_timestamp(nil), do: nil
  defp encode_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp decode_timestamp(nil), do: nil

  defp decode_timestamp(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_type(str) when str in @known_types, do: {:ok, String.to_atom(str)}
  defp parse_type(_), do: {:error, :unknown_event_type}

  @doc """
  JSON-friendly schema description of the event wire protocol. Consumed by
  `GET /schema/events` so third-party clients can target the protocol without
  reading Elixir source.
  """
  @spec schema() :: map()
  def schema do
    %{
      "version" => @wire_version,
      "envelope" => %{
        "v" => "integer (wire version)",
        "type" => "string (event type)",
        "payload" => "object (see types)",
        "session_id" => "string | null",
        "seq" => "integer | null",
        "timestamp" => "string (ISO8601) | null"
      },
      "types" => %{
        "text_delta" => %{"text" => "string"},
        "thinking_delta" => %{"text" => "string"},
        "tool_use_start" => %{"name" => "string", "id" => "string"},
        "tool_result" => %{
          "name" => "string",
          "id" => "string | null",
          "output" => "string",
          "is_error" => "boolean"
        },
        "turn_complete" => %{"usage" => "usage_map"},
        "error" => %{"message" => "string"},
        "interrupted" => %{"message" => "string"},
        "permission_request" => %{
          "request_id" => "string",
          "tool" => "string",
          "input" => "string"
        },
        "permission_decision" => %{
          "request_id" => "string",
          "decision" => "allow | deny | always_allow"
        },
        "message_added" => %{"role" => "string"},
        "usage_updated" => %{"usage" => "usage_map"},
        "model_changed" => %{"model" => "string"},
        "session_cleared" => %{},
        "command_result" => %{
          "name" => "string",
          "text" => "string | null",
          "state_patch" => "object"
        },
        "info" => %{"message" => "string"}
      },
      "usage_map" => %{
        "input_tokens" => "integer",
        "output_tokens" => "integer",
        "cache_creation_tokens" => "integer",
        "cache_read_tokens" => "integer",
        "turns" => "integer",
        "total_tokens" => "integer"
      }
    }
  end
end
