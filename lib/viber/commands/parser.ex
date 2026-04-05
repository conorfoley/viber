defmodule Viber.Commands.Parser do
  @moduledoc """
  Parses slash command input with fuzzy matching.
  """

  alias Viber.Commands.Registry

  @type parse_result ::
          {:command, String.t(), [String.t()]}
          | {:suggestion, String.t(), [String.t()]}
          | {:not_command, String.t()}

  @spec parse(String.t()) :: parse_result()
  def parse("/" <> rest) do
    parts = String.split(String.trim(rest), ~r/\s+/, parts: 2)

    {name, args} =
      case parts do
        [n] -> {n, []}
        [n, a] -> {n, String.split(a, ~r/\s+/)}
      end

    name = String.downcase(name)

    case Registry.get(name) do
      {:ok, spec} ->
        {:command, spec.name, args}

      :error ->
        suggestions =
          Registry.names()
          |> Enum.filter(fn known -> String.jaro_distance(name, known) > 0.8 end)
          |> Enum.sort_by(fn known -> String.jaro_distance(name, known) end, :desc)

        if suggestions != [] do
          {:suggestion, name, suggestions}
        else
          {:not_command, "/" <> rest}
        end
    end
  end

  def parse(input), do: {:not_command, input}

  @spec command?(String.t()) :: boolean()
  def command?("/" <> _), do: true
  def command?(_), do: false
end
