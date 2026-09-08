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
    pos_lf = :binary.match(buf, "\n\n")
    pos_crlf = :binary.match(buf, "\r\n\r\n")

    case {pos_lf, pos_crlf} do
      {:nomatch, :nomatch} ->
        nil

      {{start_lf, _}, :nomatch} ->
        do_split(buf, start_lf, 2)

      {:nomatch, {start_crlf, _}} ->
        do_split(buf, start_crlf, 4)

      {{start_lf, _}, {start_crlf, _}} ->
        if start_lf <= start_crlf do
          do_split(buf, start_lf, 2)
        else
          do_split(buf, start_crlf, 4)
        end
    end
  end

  defp do_split(buf, start, len) do
    frame = binary_part(buf, 0, start)
    rest = binary_part(buf, start + len, byte_size(buf) - start - len)
    {frame, rest}
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
    frame
    |> String.trim()
    |> parse_trimmed_frame()
  end

  defp parse_trimmed_frame(""), do: {:ok, nil}

  defp parse_trimmed_frame(trimmed) do
    {event_name, data_lines} = parse_frame_lines(trimmed)
    build_frame_result(event_name, data_lines)
  end

  defp parse_frame_lines(trimmed) do
    trimmed
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing(&1, "\r"))
    |> Enum.reduce({nil, []}, &accumulate_frame_line/2)
  end

  defp accumulate_frame_line(line, {ev, data}) do
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
  end

  defp build_frame_result("ping", _data_lines), do: {:ok, nil}
  defp build_frame_result(_event_name, []), do: {:ok, nil}

  defp build_frame_result(_event_name, data_lines) do
    data_lines
    |> Enum.reverse()
    |> Enum.join("\n")
    |> decode_frame_payload()
  end

  defp decode_frame_payload("[DONE]"), do: {:ok, nil}

  defp decode_frame_payload(payload) do
    case Jason.decode(payload) do
      {:ok, json} ->
        decode_frame_json(json)

      {:error, reason} ->
        {:error, %Viber.API.Error{type: :json, message: "json error: #{inspect(reason)}"}}
    end
  end

  defp decode_frame_json(json) do
    {:ok, Viber.API.Types.decode_stream_event(json)}
  end
end
