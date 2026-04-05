defmodule Viber.Tools.Builtins.FileOps do
  @moduledoc """
  File read, write, and edit operations.
  """

  @max_lines 2000
  @max_line_length 2000

  @spec read(map()) :: {:ok, String.t()} | {:error, String.t()}
  def read(%{"path" => path} = input) do
    offset = input["offset"] || 0
    limit = input["limit"] || @max_lines

    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        total = length(lines)
        start_idx = min(offset, total)
        end_idx = min(start_idx + limit, total)

        selected =
          lines
          |> Enum.slice(start_idx, end_idx - start_idx)
          |> Enum.with_index(start_idx + 1)
          |> Enum.map(fn {line, num} ->
            truncated =
              if String.length(line) > @max_line_length,
                do: String.slice(line, 0, @max_line_length) <> "...",
                else: line

            "#{String.pad_leading(Integer.to_string(num), 6)}\t#{truncated}"
          end)
          |> Enum.join("\n")

        {:ok, "Lines #{start_idx + 1}-#{end_idx} of #{total} from #{path}:\n#{selected}"}

      {:error, reason} ->
        {:error, "Failed to read #{path}: #{inspect(reason)}"}
    end
  end

  def read(_), do: {:error, "Missing required parameter: path"}

  @spec write(map()) :: {:ok, String.t()} | {:error, String.t()}
  def write(%{"path" => path, "content" => content}) do
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, content) do
      bytes = byte_size(content)
      {:ok, "Wrote #{bytes} bytes to #{path}"}
    else
      {:error, reason} -> {:error, "Failed to write #{path}: #{inspect(reason)}"}
    end
  end

  def write(_), do: {:error, "Missing required parameters: path, content"}

  @spec edit(map()) :: {:ok, String.t()} | {:error, String.t()}
  def edit(%{"path" => path, "old_string" => old_string, "new_string" => new_string} = input) do
    replace_all = input["replace_all"] || false

    if old_string == new_string do
      {:error, "old_string and new_string must differ"}
    else
      case File.read(path) do
        {:ok, content} ->
          count = count_occurrences(content, old_string)

          cond do
            count == 0 ->
              {:error, "old_string not found in #{path}"}

            count > 1 and not replace_all ->
              {:error,
               "old_string found #{count} times in #{path}; set replace_all to true or provide a more specific match"}

            true ->
              new_content =
                if replace_all do
                  String.replace(content, old_string, new_string)
                else
                  replace_first(content, old_string, new_string)
                end

              case File.write(path, new_content) do
                :ok ->
                  replacements = if replace_all, do: count, else: 1
                  {:ok, "Replaced #{replacements} occurrence(s) in #{path}"}

                {:error, reason} ->
                  {:error, "Failed to write #{path}: #{inspect(reason)}"}
              end
          end

        {:error, reason} ->
          {:error, "Failed to read #{path}: #{inspect(reason)}"}
      end
    end
  end

  def edit(_), do: {:error, "Missing required parameters: path, old_string, new_string"}

  defp count_occurrences(string, pattern) do
    string
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end

  defp replace_first(string, old, new) do
    case String.split(string, old, parts: 2) do
      [before, after_match] -> before <> new <> after_match
      [^string] -> string
    end
  end
end
