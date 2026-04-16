defmodule Viber.Commands.Handlers.Toolset do
  @moduledoc """
  Handler for the /toolset command. Shows, enables, or disables tool groups.
  """

  alias Viber.Tools.{Registry, Toolsets}

  @spec execute([String.t()], map()) ::
          {:ok, String.t()} | {:error, String.t()} | {:update_toolsets, [atom()] | nil}
  def execute([], context), do: execute(["list"], context)

  def execute(["list"], context) do
    enabled = context[:enabled_toolsets]
    all_toolsets = Toolsets.all()

    lines =
      Enum.map(all_toolsets, fn ts ->
        active =
          cond do
            enabled == nil -> true
            ts.name in enabled -> true
            true -> false
          end

        tool_count =
          Registry.builtin_specs()
          |> Enum.count(fn spec -> spec.toolset == ts.name end)

        status = if active, do: "[on] ", else: "[off]"
        "  #{status} #{ts.label} (#{ts.name}) — #{ts.description} [#{tool_count} tools]"
      end)

    note =
      if enabled == nil,
        do: "\nAll toolsets enabled (default).",
        else: "\nEnabled: #{Enum.join(enabled, ", ")}"

    {:ok,
     "Toolsets:\n#{Enum.join(lines, "\n")}#{note}\n\nUsage: /toolset enable <name> | /toolset disable <name> | /toolset reset"}
  end

  def execute(["enable", name | _], context) do
    case Toolsets.parse(name) do
      {:ok, toolset} ->
        enabled = context[:enabled_toolsets]

        new_enabled =
          cond do
            enabled == nil ->
              Toolsets.all_names()
              |> Enum.filter(fn n -> n != toolset end)
              |> then(fn rest ->
                [toolset | rest]
              end)

            toolset in enabled ->
              enabled

            true ->
              [toolset | enabled]
          end

        {:update_toolsets, new_enabled}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(["disable", name | _], context) do
    case Toolsets.parse(name) do
      {:ok, :core} ->
        {:error, "The :core toolset cannot be disabled."}

      {:ok, toolset} ->
        current = context[:enabled_toolsets] || Toolsets.all_names()
        new_enabled = Enum.filter(current, fn n -> n != toolset end)
        {:update_toolsets, new_enabled}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(["reset"], _context) do
    {:update_toolsets, nil}
  end

  def execute([unknown | _], _context) do
    {:error, "Unknown subcommand: #{unknown}. Use: list, enable <name>, disable <name>, reset"}
  end
end
