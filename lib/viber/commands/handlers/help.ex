defmodule Viber.Commands.Handlers.Help do
  @moduledoc """
  Handler for the /help command.
  """

  use Viber.Commands.Handler

  alias Viber.Commands.Registry

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute([], _context) do
    groups =
      Registry.all()
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {cat, _} -> category_order(cat) end)

    lines =
      Enum.flat_map(groups, fn {category, commands} ->
        header =
          IO.ANSI.format([:bright, :blue, "\n  #{category_title(category)}", :reset])
          |> IO.chardata_to_string()

        cmds =
          Enum.map(commands, fn cmd ->
            usage =
              IO.ANSI.format([:cyan, "  #{cmd.usage}", :reset])
              |> IO.chardata_to_string()

            desc =
              IO.ANSI.format([:faint, " — #{cmd.description}", :reset])
              |> IO.chardata_to_string()

            "  #{usage}#{desc}"
          end)

        [header | cmds]
      end)

    {:ok, Enum.join(lines, "\n")}
  end

  def execute([name | _], _context) do
    case Registry.get(name) do
      {:ok, spec} ->
        output =
          IO.ANSI.format([
            :bright,
            :cyan,
            spec.name,
            :reset,
            :faint,
            " — ",
            :reset,
            spec.description,
            "\n",
            :faint,
            "Usage: ",
            :reset,
            :cyan,
            spec.usage
          ])
          |> IO.chardata_to_string()

        {:ok, output}

      :error ->
        {:error, "Unknown command: #{name}"}
    end
  end

  defp category_title(:info), do: "Info"
  defp category_title(:session), do: "Session"
  defp category_title(:config), do: "Config"
  defp category_title(:project), do: "Project"

  defp category_order(:info), do: 0
  defp category_order(:session), do: 1
  defp category_order(:config), do: 2
  defp category_order(:project), do: 3
end
