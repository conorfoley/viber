defmodule Viber.Commands.Handlers.Config do
  @moduledoc """
  Handler for the /config command.
  """

  use Viber.Commands.Handler

  alias Viber.Runtime.Config

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute([], context) do
    config = context[:config] || %Config{}

    lines = [
      "Model: #{config.model || "(default)"}",
      "Permission mode: #{config.permission_mode || "(default)"}",
      "MCP servers: #{map_size(config.mcp_servers)}",
      "Custom instructions: #{if config.custom_instructions, do: "yes", else: "no"}",
      "Loaded from: #{format_sources(config.loaded_entries)}"
    ]

    {:ok, Enum.join(lines, "\n")}
  end

  def execute([key | _], context) do
    config = context[:config] || %Config{}
    value = Config.get(config, key)

    if value do
      {:ok, "#{key}: #{inspect(value)}"}
    else
      {:ok, "#{key}: (not set)"}
    end
  end

  defp format_sources([]), do: "(none)"

  defp format_sources(entries) do
    Enum.map_join(entries, ", ", fn {source, path} ->
      "#{source}:#{Path.basename(path)}"
    end)
  end
end
