defmodule Viber.Runtime.FileRefs do
  @moduledoc """
  Stateless utility for resolving file paths and glob patterns and formatting
  their contents as context blocks for LLM messages.
  """

  @max_files 50
  @max_size 200_000

  @type resolved :: {:ok, String.t(), String.t()} | {:error, String.t(), String.t()}

  @spec resolve_pattern(String.t(), String.t()) :: [resolved()]
  def resolve_pattern(pattern, base_dir) do
    expanded = Path.expand(pattern, base_dir)
    paths = Path.wildcard(expanded)

    case paths do
      [] ->
        [{:error, pattern, "no files matched"}]

      paths ->
        {paths, truncated?} =
          if length(paths) > @max_files do
            {Enum.take(paths, @max_files), true}
          else
            {paths, false}
          end

        results = Enum.map(paths, &read_file/1)

        if truncated? do
          results ++
            [
              {:error, pattern,
               "results truncated to #{@max_files} files (more files matched but were omitted)"}
            ]
        else
          results
        end
    end
  end

  @spec format_block(String.t(), String.t()) :: String.t()
  def format_block(path, content) do
    "<file: #{path}>\n#{content}\n</file>"
  end

  @spec format_results([resolved()]) :: {String.t(), [String.t()]}
  def format_results(results) do
    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _, _} -> true
        {:error, _, _} -> false
      end)

    combined =
      Enum.map_join(successes, "\n\n", fn {:ok, path, content} -> format_block(path, content) end)

    errors =
      Enum.map(failures, fn {:error, pattern, reason} ->
        "Error: #{pattern}: #{reason}"
      end)

    {combined, errors}
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} ->
        content =
          if byte_size(content) > @max_size do
            content <>
              "\n\n[Warning: file exceeds 200 KB; content may be truncated by the LLM context window]"
          else
            content
          end

        {:ok, path, content}

      {:error, reason} ->
        {:error, path, :file.format_error(reason) |> List.to_string()}
    end
  end
end
