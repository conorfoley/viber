defmodule Viber.API.SSEParser do
  @moduledoc """
  Stateful SSE frame parser for streaming LLM responses.
  """

  @type t :: %__MODULE__{buffer: binary()}
  defstruct buffer: ""

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec next_frame(binary()) :: {binary(), binary()} | nil
  def next_frame(buf) do
    cond do
      (pos = :binary.match(buf, "\n\n")) != :nomatch ->
        {start, _len} = pos
        frame = binary_part(buf, 0, start)
        rest = binary_part(buf, start + 2, byte_size(buf) - start - 2)
        {frame, rest}

      (pos = :binary.match(buf, "\r\n\r\n")) != :nomatch ->
        {start, _len} = pos
        frame = binary_part(buf, 0, start)
        rest = binary_part(buf, start + 4, byte_size(buf) - start - 4)
        {frame, rest}

      true ->
        nil
    end
  end

  @spec push(t(), binary()) :: {:ok, t(), [Viber.API.Types.stream_event()]} | {:error, term()}
  def push(%__MODULE__{buffer: buf} = _parser, chunk) when is_binary(chunk) do
    buf = buf <> chunk
    extract_frames(%__MODULE__{buffer: buf}, [])
  end

  @spec finish(t()) :: {:ok, [Viber.API.Types.stream_event()]} | {:error, term()}
  def finish(%__MODULE__{buffer: buf}) do
    if String.trim(buf) == "" do
      {:ok, []}
    else
      case parse_frame(buf) do
        {:ok, nil} -> {:ok, []}
        {:ok, event} -> {:ok, [event]}
        {:error, _} = err -> err
      end
    end
  end

  defp extract_frames(%__MODULE__{buffer: buf} = parser, acc) do
    case next_frame(buf) do
      {frame, rest} ->
        case parse_frame(frame) do
          {:ok, nil} -> extract_frames(%__MODULE__{buffer: rest}, acc)
          {:ok, event} -> extract_frames(%__MODULE__{buffer: rest}, [event | acc])
          {:error, _} = err -> err
        end

      nil ->
        {:ok, parser, Enum.reverse(acc)}
    end
  end

  defp parse_frame(frame) do
    trimmed = String.trim(frame)

    if trimmed == "" do
      {:ok, nil}
    else
      {event_name, data_lines} =
        trimmed
        |> String.split("\n")
        |> Enum.map(&String.trim_trailing(&1, "\r"))
        |> Enum.reduce({nil, []}, fn line, {ev, data} ->
          cond do
            String.starts_with?(line, ":") ->
              {ev, data}

            String.starts_with?(line, "event:") ->
              {String.trim(String.trim_leading(line, "event:")), data}

            String.starts_with?(line, "data:") ->
              {ev, [String.trim_leading(String.trim_leading(line, "data:"), " ") | data]}

            true ->
              {ev, data}
          end
        end)

      cond do
        event_name == "ping" ->
          {:ok, nil}

        data_lines == [] ->
          {:ok, nil}

        true ->
          payload = data_lines |> Enum.reverse() |> Enum.join("\n")

          if payload == "[DONE]" do
            {:ok, nil}
          else
            case Jason.decode(payload) do
              {:ok, json} ->
                case Viber.API.Types.decode_stream_event(json) do
                  nil -> {:ok, nil}
                  event -> {:ok, event}
                end

              {:error, reason} ->
                {:error, %Viber.API.Error{type: :json, message: "json error: #{inspect(reason)}"}}
            end
          end
      end
    end
  end
end
