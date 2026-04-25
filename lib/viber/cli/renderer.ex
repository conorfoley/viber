defmodule Viber.CLI.Renderer do
  @moduledoc """
  Terminal rendering with Markdown-to-ANSI conversion and Owl-based widgets.
  """

  alias Viber.Runtime.Usage

  @terminal_width 80
  @tool_icons %{
    "bash" => "⌨",
    "execute_bash" => "⌨",
    "read_file" => "📄",
    "write_file" => "✏",
    "edit_file" => "✏",
    "list_files" => "📁",
    "glob" => "🔍",
    "grep" => "🔍",
    "ls" => "📁",
    "web_fetch" => "🌐"
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

  defp read_single_char do
    case File.open("/dev/tty", [:read, :raw]) do
      {:ok, tty} -> read_single_char_tty(tty)
      {:error, _} -> read_single_char_fallback()
    end
  end

  defp read_single_char_tty(tty) do
    System.cmd("sh", ["-c", "stty raw -echo < /dev/tty"], stderr_to_stdout: true)

    try do
      case IO.binread(tty, 1) do
        <<c>> -> c
        _ -> ?\n
      end
    after
      System.cmd("sh", ["-c", "stty -raw echo < /dev/tty"], stderr_to_stdout: true)
      File.close(tty)
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
