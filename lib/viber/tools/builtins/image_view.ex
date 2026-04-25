defmodule Viber.Tools.Builtins.ImageView do
  @moduledoc """
  Read image file metadata and optionally encode as base64 for LLM vision input.
  """

  @max_file_size 10_000_000
  @supported_extensions ~w(.png .jpg .jpeg .gif .webp .bmp .svg)

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"path" => path} = input) do
    include_data = input["include_data"] || false

    case validate_image(path) do
      :ok ->
        case File.stat(path) do
          {:ok, stat} ->
            ext = Path.extname(path) |> String.downcase()
            mime = mime_type(ext)

            lines = [
              "Image: #{path}",
              "Size: #{format_size(stat.size)}",
              "Type: #{mime}",
              "Modified: #{NaiveDateTime.to_string(stat.mtime |> naive_from_erl())}"
            ]

            lines =
              if include_data and stat.size <= @max_file_size do
                case File.read(path) do
                  {:ok, data} ->
                    b64 = Base.encode64(data)
                    lines ++ ["", "Base64 (#{String.length(b64)} chars):", b64]

                  {:error, reason} ->
                    lines ++ ["", "(Failed to read file data: #{reason})"]
                end
              else
                if include_data and stat.size > @max_file_size do
                  lines ++
                    ["", "(File too large to include inline, max #{format_size(@max_file_size)})"]
                else
                  lines
                end
              end

            {:ok, Enum.join(lines, "\n")}

          {:error, reason} ->
            {:error, "Failed to read file metadata: #{reason}"}
        end

      {:error, _} = err ->
        err
    end
  end

  def execute(_), do: {:error, "Missing required parameter: path"}

  defp validate_image(path) do
    ext = Path.extname(path) |> String.downcase()

    cond do
      not File.exists?(path) ->
        {:error, "File not found: #{path}"}

      ext not in @supported_extensions ->
        {:error,
         "Unsupported image format: #{ext}. Supported: #{Enum.join(@supported_extensions, ", ")}"}

      true ->
        :ok
    end
  end

  defp mime_type(".png"), do: "image/png"
  defp mime_type(".jpg"), do: "image/jpeg"
  defp mime_type(".jpeg"), do: "image/jpeg"
  defp mime_type(".gif"), do: "image/gif"
  defp mime_type(".webp"), do: "image/webp"
  defp mime_type(".bmp"), do: "image/bmp"
  defp mime_type(".svg"), do: "image/svg+xml"
  defp mime_type(ext), do: "application/octet-stream (#{ext})"

  defp format_size(bytes) when bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_size(bytes) when bytes >= 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_size(bytes), do: "#{bytes} bytes"

  defp naive_from_erl({{y, m, d}, {h, min, s}}) do
    NaiveDateTime.new!(y, m, d, h, min, s)
  end
end
