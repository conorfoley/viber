defmodule Viber.Commands.Handlers.Effort do
  @moduledoc """
  Handler for the /effort command.

  Shows or sets the reasoning effort (`output_config.effort`) for the
  session. Effort is the recommended lever for controlling token spend:
  lower effort means shallower thinking, fewer and more consolidated tool
  calls, and terser output.
  """

  use Viber.Commands.Handler

  alias Viber.API.Client
  alias Viber.Runtime.Config

  @spec execute([String.t()], map()) ::
          {:ok, String.t()} | {:error, String.t()} | {:update_config, map(), String.t()}
  def execute([], context) do
    current = current_effort(context[:config])

    {:ok,
     Enum.join(
       [
         "Current effort: #{current || "default (high)"}",
         "Available levels: #{Enum.join(Client.effort_levels(), ", ")}",
         "Lower effort = fewer thinking/output tokens; xhigh/max for the hardest work.",
         "Usage: /effort <level> | /effort reset"
       ],
       "\n"
     )}
  end

  def execute([arg | _], _context) when arg in ["reset", "default"] do
    {:update_config, %{effort: nil}, "Effort reset to model default (high)."}
  end

  def execute([level | _], _context) do
    if level in Client.effort_levels() do
      {:update_config, %{effort: level}, "Effort set to #{level}.#{note(level)}"}
    else
      {:error,
       "Unknown effort level '#{level}'. Available: #{Enum.join(Client.effort_levels(), ", ")}"}
    end
  end

  defp current_effort(%Config{effort: effort}), do: effort
  defp current_effort(_), do: nil

  defp note("low"), do: " Good for routine or mechanical work."

  defp note("xhigh"),
    do: " Best for hard coding/agentic tasks (not on the 4.6 family — clamped to high)."

  defp note("max"), do: " Use when correctness matters more than cost."
  defp note(_), do: ""
end
