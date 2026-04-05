defmodule Viber.Tools.Builtins.MultiEdit do
  @moduledoc """
  Apply multiple text replacements to one or more files atomically.

  Each edit is validated before any writes occur. If any edit fails validation
  (e.g. old_string not found, ambiguous match), the entire batch is aborted
  and no files are modified.
  """

  @type edit :: %{
          String.t() => String.t() | boolean()
        }

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"edits" => edits}) when is_list(edits) and length(edits) > 0 do
    with :ok <- validate_edits(edits),
         {:ok, originals} <- read_all_files(edits),
         {:ok, patched} <- apply_all_edits(edits, originals) do
      write_all(originals, patched)
    end
  end

  def execute(%{"edits" => []}), do: {:error, "edits array must not be empty"}
  def execute(_), do: {:error, "Missing required parameter: edits (array)"}

  defp validate_edits(edits) do
    Enum.reduce_while(edits, {:ok, 0}, fn edit, {:ok, idx} ->
      case validate_edit(edit, idx) do
        :ok -> {:cont, {:ok, idx + 1}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  defp validate_edit(edit, idx) do
    cond do
      not is_binary(edit["path"]) ->
        {:error, "Edit #{idx}: missing required field 'path'"}

      not is_binary(edit["old_string"]) ->
        {:error, "Edit #{idx}: missing required field 'old_string'"}

      not is_binary(edit["new_string"]) ->
        {:error, "Edit #{idx}: missing required field 'new_string'"}

      edit["old_string"] == edit["new_string"] ->
        {:error, "Edit #{idx}: old_string and new_string must differ"}

      true ->
        :ok
    end
  end

  defp read_all_files(edits) do
    paths = edits |> Enum.map(& &1["path"]) |> Enum.uniq()

    Enum.reduce_while(paths, {:ok, %{}}, fn path, {:ok, acc} ->
      case File.read(path) do
        {:ok, content} -> {:cont, {:ok, Map.put(acc, path, content)}}
        {:error, reason} -> {:halt, {:error, "Failed to read #{path}: #{inspect(reason)}"}}
      end
    end)
  end

  defp apply_all_edits(edits, file_contents) do
    Enum.reduce_while(Enum.with_index(edits), {:ok, file_contents}, fn {edit, idx},
                                                                       {:ok, contents} ->
      path = edit["path"]
      old = edit["old_string"]
      new = edit["new_string"]
      replace_all = edit["replace_all"] || false
      content = contents[path]

      count = count_occurrences(content, old)

      cond do
        count == 0 ->
          {:halt, {:error, "Edit #{idx}: old_string not found in #{path}"}}

        count > 1 and not replace_all ->
          {:halt,
           {:error,
            "Edit #{idx}: old_string found #{count} times in #{path}; set replace_all or use a more specific match"}}

        true ->
          new_content =
            if replace_all do
              String.replace(content, old, new)
            else
              replace_first(content, old, new)
            end

          {:cont, {:ok, Map.put(contents, path, new_content)}}
      end
    end)
  end

  defp write_all(originals, patched) do
    tmp_suffix = ".viber_tmp_#{System.unique_integer([:positive])}"

    tmp_pairs =
      Enum.map(patched, fn {path, new_content} ->
        {path, path <> tmp_suffix, new_content}
      end)

    case write_temp_files(tmp_pairs) do
      :ok ->
        commit_renames(tmp_pairs, originals)

      {:error, _} = err ->
        cleanup_temps(tmp_pairs)
        err
    end
  end

  defp write_temp_files(tmp_pairs) do
    Enum.reduce_while(tmp_pairs, :ok, fn {path, tmp, content}, :ok ->
      case File.write(tmp, content) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, "Failed to write #{path}: #{inspect(reason)}"}}
      end
    end)
  end

  defp commit_renames(tmp_pairs, originals) do
    case rename_all(tmp_pairs, originals, []) do
      {:ok, _} ->
        file_count = length(tmp_pairs)
        paths = Enum.map_join(tmp_pairs, ", ", fn {path, _, _} -> path end)

        {:ok,
         "Applied edits to #{file_count} file#{if file_count == 1, do: "", else: "s"}: #{paths}"}

      {:error, reason, rolled_back_paths} ->
        _ = rolled_back_paths
        cleanup_temps(tmp_pairs)
        {:error, reason}
    end
  end

  defp rename_all([], _originals, committed), do: {:ok, committed}

  defp rename_all([{path, tmp, _content} | rest], originals, committed) do
    case File.rename(tmp, path) do
      :ok ->
        rename_all(rest, originals, [path | committed])

      {:error, reason} ->
        rollback(committed, originals)
        {:error, "Failed to commit #{path}: #{inspect(reason)}", committed}
    end
  end

  defp rollback(committed_paths, originals) do
    Enum.each(committed_paths, fn path ->
      case Map.fetch(originals, path) do
        {:ok, original_content} -> File.write(path, original_content)
        :error -> :ok
      end
    end)
  end

  defp cleanup_temps(tmp_pairs) do
    Enum.each(tmp_pairs, fn {_path, tmp, _content} -> File.rm(tmp) end)
  end

  defp count_occurrences(string, pattern) do
    length(String.split(string, pattern)) - 1
  end

  defp replace_first(string, old, new) do
    case String.split(string, old, parts: 2) do
      [before, after_match] -> before <> new <> after_match
      [^string] -> string
    end
  end
end
