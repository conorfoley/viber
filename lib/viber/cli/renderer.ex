defmodule Viber.CLI.Renderer do
  @moduledoc """
  Terminal rendering with Markdown-to-ANSI conversion and Owl-based widgets.
  """

  alias Viber.Runtime.Usage

  @terminal_width 80
  @tool_icons %{
    "bash" => "⌨️",
    "execute_bash" => "⌨️",
    "read_file" => "📖",
    "write_file" => "✍️",
    "edit_file" => "✏️",
    "multi_edit" => "🧩",
    "list_files" => "🗂️",
    "glob_search" => "🎯",
    "glob" => "🎯",
    "grep_search" => "🔍",
    "grep" => "🔍",
    "ls" => "📁",
    "web_fetch" => "🌐",
    "web_search" => "🔎",
    "clipboard" => "📋",
    "jq" => "🪄",
    "user_input" => "💬",
    "mix_task" => "📦",
    "test_runner" => "🧪",
    "diagnostics" => "🩺",
    "git" => "🌿",
    "formatter" => "🪮",
    "ecto_schema_inspector" => "🏗️",
    "mysql_query" => "🗄️",
    "mysql_schema" => "🗺️",
    "mysql_explain" => "📊",
    "data_export" => "📤",
    "data_transform" => "🧬",
    "scheduler" => "⏰",
    "skill" => "📘",
    "spawn_agent" => "🤖",
    "hex_package_info" => "📮",
    "docs_lookup" => "📚",
    "image_view" => "🖼️",
    "browser_click" => "👆",
    "browser_type" => "⌨️",
    "browser_scroll" => "🖱️",
    "browser_navigate" => "🧭",
    "browser_focus" => "🕹️",
    "browser_get_accessibility_tree" => "🌲",
    "browser_wait_for_load" => "⏳"
  }

  @spec render_markdown(String.t()) :: IO.chardata()
  def render_markdown(text) do
    text
    |> String.split("\n")
    |> render_lines([], false, nil)
    |> Enum.reverse()
    |> Enum.intersperse("\n")
  end

  defp render_lines([], acc, true, lang) do
    [render_code_block_end(lang) | acc]
  end

  defp render_lines([], acc, false, _lang), do: acc

  defp render_lines(["```" <> lang | rest], acc, false, _lang) do
    trimmed = String.trim(lang)
    label = if trimmed == "", do: nil, else: trimmed
    render_lines(rest, [render_code_block_start(label) | acc], true, label)
  end

  defp render_lines(["```" <> _ | rest], acc, true, lang) do
    render_lines(rest, [render_code_block_end(lang) | acc], false, nil)
  end

  defp render_lines([line | rest], acc, true, lang) do
    render_lines(rest, [render_code_line(line) | acc], true, lang)
  end

  defp render_lines([line | rest], acc, false, lang) do
    render_lines(rest, [render_line(line) | acc], false, lang)
  end

  defp render_code_block_start(nil) do
    width = terminal_width()

    [
      IO.ANSI.faint(),
      IO.ANSI.cyan(),
      " ┌",
      String.duplicate("─", width - 4),
      "┐",
      IO.ANSI.reset()
    ]
  end

  defp render_code_block_start(label) do
    width = terminal_width()
    remaining = width - 4 - String.length(label) - 1
    remaining = max(remaining, 1)

    [
      IO.ANSI.faint(),
      IO.ANSI.cyan(),
      " ┌─",
      IO.ANSI.reset(),
      IO.ANSI.cyan(),
      label,
      IO.ANSI.faint(),
      String.duplicate("─", remaining),
      "┐",
      IO.ANSI.reset()
    ]
  end

  defp render_code_block_end(_lang) do
    width = terminal_width()

    [
      IO.ANSI.faint(),
      IO.ANSI.cyan(),
      " └",
      String.duplicate("─", width - 4),
      "┘",
      IO.ANSI.reset()
    ]
  end

  defp render_code_line(line) do
    [
      IO.ANSI.faint(),
      IO.ANSI.cyan(),
      " │",
      IO.ANSI.reset(),
      " ",
      IO.ANSI.yellow(),
      line,
      IO.ANSI.reset()
    ]
  end

  @spec render_sub_agent_tool_use(String.t(), String.t()) :: IO.chardata()
  def render_sub_agent_tool_use(name, _id) do
    icon = Map.get(@tool_icons, name, "⚡")

    label =
      [
        Owl.Data.tag("  ↳ ", :faint),
        Owl.Data.tag(icon <> " ", [:faint, :yellow]),
        Owl.Data.tag(name, [:faint, :yellow])
      ]
      |> Owl.Data.to_chardata()

    ["\n", label, "\n"]
  end

  @spec render_sub_agent_tool_result(String.t(), boolean()) :: IO.chardata()
  def render_sub_agent_tool_result(output, is_error) do
    truncated = String.slice(output, 0, 300)
    lines = String.split(truncated, "\n")
    display_lines = Enum.take(lines, 3)
    remaining = length(lines) - 3

    color = if is_error, do: :red, else: :green

    content =
      display_lines
      |> Enum.join("\n")
      |> Owl.Data.tag(:faint)
      |> Owl.Data.add_prefix(Owl.Data.tag("  ↳   │ ", [:faint, color]))

    suffix =
      if remaining > 0 do
        ["\n", IO.ANSI.faint(), "  ↳   … #{remaining} more lines", IO.ANSI.reset()]
      else
        []
      end

    [Owl.Data.to_chardata(content), suffix, "\n"]
  end

  @spec render_sub_agent_text_delta(String.t()) :: IO.chardata()
  def render_sub_agent_text_delta(text) do
    [IO.ANSI.faint(), text, IO.ANSI.reset()]
  end

  @spec render_sub_agent_thinking(String.t()) :: IO.chardata()
  def render_sub_agent_thinking(text) do
    [IO.ANSI.faint(), IO.ANSI.italic(), text, IO.ANSI.reset()]
  end

  @spec render_tool_use(String.t(), String.t()) :: IO.chardata()
  def render_tool_use(name, id) do
    icon = Map.get(@tool_icons, name, "⚡")

    tool_label =
      [
        Owl.Data.tag(icon <> " ", :yellow),
        Owl.Data.tag(name, [:bright, :yellow])
      ]

    box =
      tool_label
      |> Owl.Box.new(
        padding_x: 1,
        border_style: :solid_rounded,
        border_tag: :yellow
      )
      |> Owl.Data.to_chardata()

    _ = id
    ["\n", box, "\n"]
  end

  @spec render_tool_result(String.t(), boolean()) :: IO.chardata()
  def render_tool_result(output, is_error) do
    truncated = String.slice(output, 0, 500)
    lines = String.split(truncated, "\n")
    display_lines = Enum.take(lines, 5)
    remaining = length(lines) - 5

    color = if is_error, do: :red, else: :green
    prefix_char = if is_error, do: "✖ ", else: "✔ "
    prefix = Owl.Data.tag(prefix_char, color)

    content =
      display_lines
      |> Enum.join("\n")
      |> Owl.Data.tag(:faint)
      |> Owl.Data.add_prefix(Owl.Data.tag("  │ ", color))

    suffix =
      if remaining > 0 do
        ["\n", IO.ANSI.faint(), "  … #{remaining} more lines", IO.ANSI.reset()]
      else
        []
      end

    [Owl.Data.to_chardata(prefix), "\n", Owl.Data.to_chardata(content), suffix, "\n"]
  end

  @spec render_error(String.t()) :: IO.chardata()
  def render_error(message) do
    error =
      Owl.Data.tag(["✖ ", message], :red)
      |> Owl.Box.new(
        padding_x: 1,
        border_style: :solid_rounded,
        border_tag: :red
      )
      |> Owl.Data.to_chardata()

    [error, "\n"]
  end

  @spec render_usage(Usage.t()) :: IO.chardata()
  def render_usage(usage) do
    [
      IO.ANSI.faint(),
      "  ↑ ",
      format_tokens(usage.input_tokens),
      "  ↓ ",
      format_tokens(usage.output_tokens),
      "  Σ ",
      format_tokens(Usage.total_tokens(usage)),
      IO.ANSI.reset(),
      "\n"
    ]
  end

  @spec render_thinking(String.t()) :: IO.chardata()
  def render_thinking(text) do
    [IO.ANSI.faint(), IO.ANSI.italic(), text, IO.ANSI.reset()]
  end

  @doc """
  Display a permission request to the user and read a single-character
  response from `/dev/tty`. Returns a broker-compatible decision.
  """
  @spec prompt_permission(String.t(), String.t()) :: :allow | :deny | :always_allow
  def prompt_permission(tool_name, tool_input) do
    width = terminal_width()
    max_content_width = max(width - 6, 20)

    truncated =
      tool_input
      |> String.slice(0, 500)
      |> String.split("\n")
      |> Enum.flat_map(fn line -> chunk_string(line, max_content_width) end)
      |> Enum.join("\n")

    content =
      [
        Owl.Data.tag(tool_name, [:bright, :yellow]),
        "\n\n",
        Owl.Data.tag(truncated, :faint)
      ]

    box =
      content
      |> Owl.Box.new(
        padding_x: 1,
        padding_y: 0,
        border_style: :solid_rounded,
        border_tag: :yellow,
        title: Owl.Data.tag(" Permission Required ", :yellow)
      )
      |> Owl.Data.to_chardata()

    IO.write(["\n", box])
    IO.puts("")

    IO.write([
      IO.ANSI.yellow(),
      "  Allow? ",
      IO.ANSI.bright(),
      "[Y/n/a] ",
      IO.ANSI.reset()
    ])

    case read_single_char() do
      c when c in [?a, ?A] ->
        IO.puts("always")
        :always_allow

      c when c in [?n, ?N] ->
        IO.puts("no")
        :deny

      _ ->
        IO.puts("yes")
        :allow
    end
  end

  @doc """
  Select an item with the arrow keys. Press Enter to choose or `q` to cancel.

  Options may be plain strings or `{label, value}` tuples; the selected value is returned.
  Returns `nil` when cancelled or when no interactive terminal is available.
  """
  @spec select_option([String.t() | {String.t(), term()}], keyword()) :: term() | nil
  def select_option(options, opts \\ [])

  def select_option([], _opts), do: nil

  def select_option(options, opts) when is_list(options) do
    entries = Enum.map(options, &normalize_option/1)
    label = Keyword.get(opts, :label, "Select an option")
    max_visible = Keyword.get(opts, :max_visible, 12)
    initial_index = Keyword.get(opts, :initial_index, 0) |> clamp_index(length(entries))

    case tty_device() do
      {:ok, device} ->
        select_option_from_tty(device, entries, label, initial_index, max_visible)

      {:error, _reason} ->
        IO.write(render_error("Interactive selection requires a terminal."))
        nil
    end
  end

  defp normalize_option({label, value}), do: {to_string(label), value}
  defp normalize_option(option), do: {to_string(option), option}

  defp select_option_from_tty(device, entries, label, selected_index, max_visible) do
    case stty(device, "-g") do
      {settings, 0} ->
        stty(device, "raw -echo")
        IO.write("\e[?25l")

        try do
          view = %{
            entries: entries,
            label: label,
            count: length(entries),
            visible: min(length(entries), max(max_visible, 1))
          }

          offset = scroll_offset(0, selected_index, view)
          line_count = draw_selection(view, selected_index, offset, nil)
          selection_loop(view, selected_index, offset, line_count)
        after
          IO.write("\e[?25h")
          stty(device, String.trim(settings))
        end

      _ ->
        IO.write(render_error("Could not switch the terminal to raw mode."))
        nil
    end
  end

  defp selection_loop(view, selected_index, offset, line_count) do
    case read_selection_key() do
      :select ->
        IO.write("\r\n")
        view.entries |> Enum.at(selected_index) |> elem(1)

      :cancel ->
        IO.write("\rSelection cancelled.\r\n")
        nil

      :ignore ->
        selection_loop(view, selected_index, offset, line_count)

      move ->
        next_index = move_index(move, selected_index, view)
        next_offset = scroll_offset(offset, next_index, view)
        line_count = draw_selection(view, next_index, next_offset, line_count)
        selection_loop(view, next_index, next_offset, line_count)
    end
  end

  defp move_index(:up, index, %{count: count}), do: rem(index - 1 + count, count)
  defp move_index(:down, index, %{count: count}), do: rem(index + 1, count)
  defp move_index(:page_up, index, %{visible: visible}), do: max(index - visible, 0)

  defp move_index(:page_down, index, %{count: count, visible: visible}),
    do: min(index + visible, count - 1)

  defp move_index(:home, _index, _view), do: 0
  defp move_index(:end, _index, %{count: count}), do: count - 1

  defp scroll_offset(offset, index, %{visible: visible, count: count}) do
    offset =
      cond do
        index < offset -> index
        index >= offset + visible -> index - visible + 1
        true -> offset
      end

    offset |> min(count - visible) |> max(0)
  end

  defp draw_selection(view, selected_index, offset, previous_line_count) do
    if previous_line_count, do: IO.write("\r\e[#{previous_line_count}A")

    rows =
      view.entries
      |> Enum.slice(offset, view.visible)
      |> Enum.with_index(offset)
      |> Enum.map(fn {{text, _value}, index} ->
        if index == selected_index do
          [IO.ANSI.cyan(), IO.ANSI.bright(), "❯ ", text, IO.ANSI.reset()]
        else
          ["  ", text]
        end
      end)

    position =
      if view.count > view.visible, do: " (#{selected_index + 1}/#{view.count})", else: ""

    footer = [
      IO.ANSI.faint(),
      "↑/↓ move · Enter select · q cancel",
      position,
      IO.ANSI.reset()
    ]

    lines = [[IO.ANSI.bright(), view.label, IO.ANSI.reset()] | rows] ++ [footer]
    Enum.each(lines, fn line -> IO.write(["\r\e[2K", line, "\r\n"]) end)
    length(lines)
  end

  defp read_selection_key() do
    case read_key_byte() do
      :eof -> :cancel
      <<?\e>> -> read_escape_sequence()
      <<c>> when c in [?\r, ?\n] -> :select
      <<c>> when c in [?q, ?Q, 3, 4] -> :cancel
      <<c>> when c in [?k, 16] -> :up
      <<c>> when c in [?j, 14] -> :down
      _ -> :ignore
    end
  end

  defp read_escape_sequence() do
    case read_key_byte() do
      <<c>> when c in [?[, ?O] -> read_csi()
      <<?\e>> -> :cancel
      _ -> :ignore
    end
  end

  defp read_csi() do
    case read_key_byte() do
      <<?A>> -> :up
      <<?B>> -> :down
      <<?H>> -> :home
      <<?F>> -> :end
      <<c>> when c in ?0..?9 -> read_csi_tilde(<<c>>)
      _ -> :ignore
    end
  end

  defp read_csi_tilde(acc) do
    case read_key_byte() do
      <<?~>> -> csi_tilde_key(acc)
      <<c>> when c in ?0..?9 or c == ?; -> read_csi_tilde(acc <> <<c>>)
      _ -> :ignore
    end
  end

  defp csi_tilde_key(code) when code in ["1", "7"], do: :home
  defp csi_tilde_key(code) when code in ["4", "8"], do: :end
  defp csi_tilde_key("5"), do: :page_up
  defp csi_tilde_key("6"), do: :page_down
  defp csi_tilde_key(_), do: :ignore

  defp read_key_byte do
    case IO.getn("", 1) do
      byte when is_binary(byte) and byte != "" -> byte
      _ -> :eof
    end
  end

  defp tty_device do
    case tty_device_from_proc() do
      {:error, :no_proc} ->
        with {:error, _} <- tty_device_from_ps(), do: dev_tty()

      result ->
        result
    end
  end

  defp dev_tty do
    if File.exists?("/dev/tty"), do: {:ok, "/dev/tty"}, else: {:error, :no_tty}
  end

  defp tty_device_from_proc do
    stdin = "/proc/#{System.pid()}/fd/0"

    case File.read_link(stdin) do
      {:ok, "/dev/" <> _} -> {:ok, stdin}
      {:ok, _other} -> {:error, :stdin_not_tty}
      {:error, _reason} -> {:error, :no_proc}
    end
  end

  defp tty_device_from_ps do
    case System.cmd("ps", ["-o", "tty=", "-p", System.pid()], stderr_to_stdout: true) do
      {output, 0} ->
        case String.trim(output) do
          tty when tty in ["", "?", "??"] -> {:error, :no_ps_tty}
          tty -> {:ok, "/dev/" <> tty}
        end

      _ ->
        {:error, :no_ps_tty}
    end
  rescue
    _ -> {:error, :no_ps_tty}
  end

  defp stty(device, args) do
    System.cmd("sh", ["-c", "stty #{args} < '#{device}'"], stderr_to_stdout: true)
  end

  defp clamp_index(index, count) when is_integer(index), do: index |> max(0) |> min(count - 1)
  defp clamp_index(_index, _count), do: 0

  defp read_single_char do
    case tty_device() do
      {:ok, device} -> read_single_char_tty(device)
      {:error, _reason} -> read_single_char_fallback()
    end
  end

  defp read_single_char_tty(device) do
    stty(device, "raw -echo")

    try do
      case read_key_byte() do
        <<c>> -> c
        _ -> ?\n
      end
    after
      stty(device, "-raw echo")
    end
  rescue
    _ -> read_single_char_fallback()
  end

  defp read_single_char_fallback do
    IO.gets("")
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "a" -> ?a
      "n" -> ?n
      _ -> ?y
    end
  end

  defp chunk_string("", _width), do: [""]

  defp chunk_string(str, width) do
    str
    |> String.graphemes()
    |> Enum.chunk_every(width)
    |> Enum.map(&Enum.join/1)
  end

  defp render_line("# " <> rest) do
    [
      IO.ANSI.bright(),
      IO.ANSI.magenta(),
      "█ ",
      IO.ANSI.reset(),
      IO.ANSI.bright(),
      IO.ANSI.underline(),
      rest,
      IO.ANSI.reset()
    ]
  end

  defp render_line("## " <> rest) do
    [
      IO.ANSI.bright(),
      IO.ANSI.blue(),
      "▌ ",
      IO.ANSI.reset(),
      IO.ANSI.bright(),
      rest,
      IO.ANSI.reset()
    ]
  end

  defp render_line("### " <> rest) do
    [IO.ANSI.cyan(), "▎ ", IO.ANSI.reset(), IO.ANSI.bright(), rest, IO.ANSI.reset()]
  end

  defp render_line("#### " <> rest) do
    [IO.ANSI.faint(), "  ", IO.ANSI.reset(), IO.ANSI.bright(), rest, IO.ANSI.reset()]
  end

  defp render_line("> " <> rest) do
    [
      IO.ANSI.faint(),
      IO.ANSI.green(),
      "  ┃ ",
      IO.ANSI.reset(),
      IO.ANSI.italic(),
      render_inline(rest),
      IO.ANSI.reset()
    ]
  end

  defp render_line("---") do
    width = terminal_width()
    [IO.ANSI.faint(), String.duplicate("─", width - 2), IO.ANSI.reset()]
  end

  defp render_line("***") do
    width = terminal_width()
    [IO.ANSI.faint(), String.duplicate("─", width - 2), IO.ANSI.reset()]
  end

  defp render_line("___") do
    width = terminal_width()
    [IO.ANSI.faint(), String.duplicate("─", width - 2), IO.ANSI.reset()]
  end

  defp render_line("    - " <> rest) do
    ["      ◦ ", render_inline(rest)]
  end

  defp render_line("  - " <> rest) do
    ["    ◦ ", render_inline(rest)]
  end

  defp render_line("- " <> rest) do
    [IO.ANSI.cyan(), "  • ", IO.ANSI.reset(), render_inline(rest)]
  end

  defp render_line("* " <> rest) do
    [IO.ANSI.cyan(), "  • ", IO.ANSI.reset(), render_inline(rest)]
  end

  defp render_line("|" <> _ = line) do
    if String.contains?(line, "|") do
      render_table_line(line)
    else
      render_inline(line)
    end
  end

  defp render_line(line) do
    case Regex.match?(~r/^\d+\.\s/, line) do
      true ->
        case Regex.run(~r/^(\d+)\.\s(.*)$/, line) do
          [_, num, rest] ->
            [IO.ANSI.cyan(), "  ", num, ". ", IO.ANSI.reset(), render_inline(rest)]

          _ ->
            ["  ", render_inline(line)]
        end

      false ->
        render_inline(line)
    end
  end

  defp render_table_line(line) do
    cells =
      line
      |> String.split("|")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if Enum.all?(cells, &Regex.match?(~r/^[-:]+$/, &1)) do
      width = terminal_width()
      [IO.ANSI.faint(), "  ", String.duplicate("─", width - 4), IO.ANSI.reset()]
    else
      rendered =
        cells
        |> Enum.map(fn cell ->
          [IO.ANSI.faint(), " │ ", IO.ANSI.reset(), render_inline(cell)]
        end)

      ["  ", rendered, IO.ANSI.faint(), " │", IO.ANSI.reset()]
    end
  end

  defp render_inline(text) do
    text
    |> replace_bold()
    |> replace_italic()
    |> replace_code()
    |> replace_links()
    |> replace_strikethrough()
  end

  defp replace_bold(text) do
    Regex.replace(~r/\*\*(.+?)\*\*/, text, fn _, content ->
      IO.ANSI.bright() <> content <> IO.ANSI.reset()
    end)
  end

  defp replace_italic(text) do
    Regex.replace(~r/(?<!\*)_(.+?)_(?!_)/, text, fn _, content ->
      IO.ANSI.italic() <> content <> IO.ANSI.reset()
    end)
  end

  defp replace_code(text) do
    Regex.replace(~r/`([^`]+)`/, text, fn _, content ->
      IO.ANSI.color(237) <> IO.ANSI.cyan() <> content <> IO.ANSI.reset()
    end)
  end

  defp replace_links(text) do
    Regex.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, text, fn _, label, url ->
      IO.ANSI.underline() <>
        IO.ANSI.blue() <>
        label <>
        IO.ANSI.reset() <>
        IO.ANSI.faint() <> " (" <> url <> ")" <> IO.ANSI.reset()
    end)
  end

  defp replace_strikethrough(text) do
    Regex.replace(~r/~~(.+?)~~/, text, fn _, content ->
      IO.ANSI.faint() <> content <> IO.ANSI.reset()
    end)
  end

  defp format_tokens(n) when n >= 1_000_000 do
    :erlang.float_to_binary(n / 1_000_000, decimals: 1) <> "M"
  end

  defp format_tokens(n) when n >= 1_000 do
    :erlang.float_to_binary(n / 1_000, decimals: 1) <> "k"
  end

  defp format_tokens(n), do: Integer.to_string(n)

  defp terminal_width do
    case :io.columns() do
      {:ok, cols} -> cols
      _ -> @terminal_width
    end
  end
end
