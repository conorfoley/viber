defmodule Viber.Commands.Handlers.Help do
  @moduledoc """
  Handler for the /help command.
  """

  alias Viber.Commands.Registry

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute([], _context) do
    groups =
      Registry.all()
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {cat, _} -> category_order(cat) end)

    lines =
      Enum.flat_map(groups, fn {category, commands} ->
        header = "\n#{category_title(category)}:"
        cmds = Enum.map(commands, fn cmd -> "  #{cmd.usage} — #{cmd.description}" end)
        [header | cmds]
      end)

    {:ok, "Available commands:" <> Enum.join(lines, "\n")}
  end

  def execute([name | _], _context) do
    case Registry.get(name) do
      {:ok, spec} ->
        {:ok, "#{spec.name} — #{spec.description}\nUsage: #{spec.usage}"}

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
