defmodule Viber.CLI.Renderer do
  @moduledoc """
  Terminal rendering with basic Markdown-to-ANSI conversion.
  """

  alias Viber.Runtime.Usage

  @spec render_markdown(String.t()) :: IO.chardata()
  def render_markdown(text) do
    text
    |> String.split("\n")
    |> Enum.map(&render_line/1)
    |> Enum.intersperse("\n")
  end

  @spec render_tool_use(String.t(), String.t()) :: IO.chardata()
  def render_tool_use(name, id) do
    [
      IO.ANSI.yellow(),
      "⚡ ",
      name,
      IO.ANSI.reset(),
      IO.ANSI.faint(),
      " (",
      id,
      ")",
      IO.ANSI.reset(),
      "\n"
    ]
  end

  @spec render_tool_result(String.t(), boolean()) :: IO.chardata()
  def render_tool_result(output, is_error) do
    truncated = String.slice(output, 0, 500)
    color = if is_error, do: IO.ANSI.red(), else: IO.ANSI.green()
    [color, truncated, IO.ANSI.reset(), "\n"]
  end

  @spec render_error(String.t()) :: IO.chardata()
  def render_error(message) do
    [IO.ANSI.red(), "Error: ", message, IO.ANSI.reset(), "\n"]
  end

  @spec render_usage(Usage.t()) :: IO.chardata()
  def render_usage(usage) do
    [IO.ANSI.faint(), Usage.format(usage), IO.ANSI.reset(), "\n"]
  end

  defp render_line("# " <> rest) do
    [IO.ANSI.bright(), IO.ANSI.underline(), rest, IO.ANSI.reset()]
  end

  defp render_line("## " <> rest) do
    [IO.ANSI.bright(), rest, IO.ANSI.reset()]
  end

  defp render_line("### " <> rest) do
    [IO.ANSI.bright(), rest, IO.ANSI.reset()]
  end

  defp render_line("```" <> _), do: [IO.ANSI.cyan(), "───", IO.ANSI.reset()]

  defp render_line("- " <> rest) do
    ["  • ", render_inline(rest)]
  end

  defp render_line(line) do
    case Regex.match?(~r/^\d+\.\s/, line) do
      true -> ["  ", render_inline(line)]
      false -> render_inline(line)
    end
  end

  defp render_inline(text) do
    text
    |> replace_bold()
    |> replace_code()
    |> replace_links()
  end

  defp replace_bold(text) do
    Regex.replace(~r/\*\*(.+?)\*\*/, text, fn _, content ->
      IO.ANSI.bright() <> content <> IO.ANSI.reset()
    end)
  end

  defp replace_code(text) do
    Regex.replace(~r/`([^`]+)`/, text, fn _, content ->
      IO.ANSI.cyan() <> content <> IO.ANSI.reset()
    end)
  end

  defp replace_links(text) do
    Regex.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, text, fn _, label, url ->
      label <> IO.ANSI.faint() <> " (" <> url <> ")" <> IO.ANSI.reset()
    end)
  end
end
