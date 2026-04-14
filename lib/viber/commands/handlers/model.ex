defmodule Viber.Commands.Handlers.Model do
  @moduledoc """
  Handler for the /model command.
  """

  alias Viber.API.Client

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute([], context) do
    model = context[:model] || "unknown"
    resolved = Client.resolve_model_alias(model)

    if model == resolved do
      {:ok, "Current model: #{model}"}
    else
      {:ok, "Current model: #{model} (#{resolved})"}
    end
  end

  def execute(["list" | _], _context) do
    aliases = Client.model_aliases()

    groups =
      aliases
      |> Enum.group_by(fn {_alias, full} -> provider_label(full) end)
      |> Enum.sort_by(fn {provider, _} -> provider end)

    lines =
      Enum.flat_map(groups, fn {provider, entries} ->
        rows =
          entries
          |> Enum.sort_by(fn {alias_, _} -> alias_ end)
          |> Enum.map(fn {alias_, full} -> "    #{alias_} → #{full}" end)

        ["  #{provider}:" | rows]
      end)

    header = "Available model aliases:"
    {:ok, Enum.join([header | lines], "\n")}
  end

  def execute([new_model | _], _context) do
    resolved = Client.resolve_model_alias(new_model)

    if new_model == resolved do
      {:ok, "Switched to model: #{new_model}"}
    else
      {:ok, "Switched to model: #{new_model} (#{resolved})"}
    end
  end

  defp provider_label("claude" <> _), do: "Anthropic"
  defp provider_label("grok" <> _), do: "xAI"
  defp provider_label("gpt-" <> _), do: "OpenAI"
  defp provider_label("ollama:" <> _), do: "Ollama"

  defp provider_label("o" <> rest) do
    case rest do
      <<c, _::binary>> when c in ?0..?9 -> "OpenAI"
      _ -> "Other"
    end
  end

  defp provider_label(_), do: "Other"
end
