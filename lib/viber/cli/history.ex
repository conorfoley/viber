defmodule Viber.CLI.History do
  @moduledoc """
  In-memory ring buffer for REPL input history with optional file persistence.

  Supports Up/Down arrow navigation through past entries, duplicate suppression,
  and blank-line filtering. Optionally persists history to `~/.viber_history`.
  """

  @default_max 500
  @default_path Path.expand("~/.viber_history")

  @type t :: %__MODULE__{
          entries: [String.t()],
          position: integer(),
          max: non_neg_integer(),
          persist_path: String.t() | nil
        }

  @enforce_keys []
  defstruct entries: [], position: -1, max: @default_max, persist_path: nil

  @doc """
  Creates a new History instance.

  ## Options

  - `:max` - maximum number of entries to keep (default: #{@default_max})
  - `:persist` - when `true`, persists to `~/.viber_history`; when a binary path,
    persists to that path; when `false` or omitted, in-memory only (default: `false`)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    max = Keyword.get(opts, :max, @default_max)

    persist_path =
      case Keyword.get(opts, :persist, false) do
        true -> @default_path
        false -> nil
        path when is_binary(path) -> path
      end

    entries =
      if persist_path do
        load_from_file(persist_path)
      else
        []
      end

    %__MODULE__{entries: entries, position: -1, max: max, persist_path: persist_path}
  end

  @doc """
  Pushes a new entry to history, resetting the navigation position.

  Blank lines and duplicates of the most recent entry are silently ignored.
  """
  @spec push(t(), String.t()) :: t()
  def push(%__MODULE__{} = history, entry) do
    trimmed = String.trim(entry)

    cond do
      trimmed == "" ->
        history

      history.entries != [] and hd(history.entries) == trimmed ->
        %{history | position: -1}

      true ->
        new_entries =
          [trimmed | history.entries]
          |> Enum.take(history.max)

        updated = %{history | entries: new_entries, position: -1}

        if updated.persist_path do
          append_to_file(updated.persist_path, trimmed)
        end

        updated
    end
  end

  @doc """
  Navigates to the previous (older) history entry (Up arrow).

  Returns `{entry_or_nil, updated_history}`. Returns `nil` when already at the
  oldest entry.
  """
  @spec previous(t()) :: {String.t() | nil, t()}
  def previous(%__MODULE__{entries: []} = history), do: {nil, history}

  def previous(%__MODULE__{entries: entries, position: pos} = history) do
    new_pos = pos + 1

    case Enum.at(entries, new_pos) do
      nil -> {Enum.at(entries, pos), history}
      entry -> {entry, %{history | position: new_pos}}
    end
  end

  @doc """
  Navigates to the next (more recent) history entry (Down arrow).

  Returns `{entry_or_nil, updated_history}`. Returns `nil` when the position
  moves past the most recent entry (back to new-input mode).
  """
  @spec next(t()) :: {String.t() | nil, t()}
  def next(%__MODULE__{position: -1} = history), do: {nil, history}

  def next(%__MODULE__{position: 0} = history) do
    {nil, %{history | position: -1}}
  end

  def next(%__MODULE__{entries: entries, position: pos} = history) do
    new_pos = pos - 1
    {Enum.at(entries, new_pos), %{history | position: new_pos}}
  end

  @doc """
  Returns the list of history entries, most recent first.
  """
  @spec to_list(t()) :: [String.t()]
  def to_list(%__MODULE__{entries: entries}), do: entries

  defp load_from_file(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reverse()

      {:error, _} ->
        []
    end
  end

  defp append_to_file(path, entry) do
    File.write(path, entry <> "\n", [:append])
  end
end
