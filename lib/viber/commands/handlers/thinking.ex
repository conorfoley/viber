defmodule Viber.Commands.Handlers.Thinking do
  @moduledoc """
  Handler for the /thinking command.

  Shows or sets the thinking mode for the session. Note that the visible
  "thinking" text is billed identically whether shown or hidden — the only
  way to spend fewer thinking tokens is lowering /effort or turning
  thinking off entirely where the model allows it.
  """

  use Viber.Commands.Handler

  alias Viber.API.Client
  alias Viber.Runtime.Config

  @spec execute([String.t()], map()) ::
          {:ok, String.t()} | {:error, String.t()} | {:update_config, map(), String.t()}
  def execute([], context) do
    current = current_mode(context[:config])

    {:ok,
     Enum.join(
       [
         "Current thinking mode: #{current || "adaptive (default)"}",
         "Available modes: #{Enum.join(Client.thinking_modes(), ", ")}",
         "Thinking is billed the same whether displayed or not; prefer /effort to cut spend.",
         "Usage: /thinking <mode> | /thinking reset"
       ],
       "\n"
     )}
  end

  def execute([arg | _], _context) when arg in ["reset", "default"] do
    {:update_config, %{thinking: nil}, "Thinking mode reset to adaptive."}
  end

  def execute(["off" | _], _context) do
    {:update_config, %{thinking: "off"},
     "Thinking disabled where the model allows it " <>
       "(Fable 5 cannot disable thinking; Opus 5 keeps it at xhigh/max effort). " <>
       "Note: this can degrade tool-call reliability — consider /effort low instead."}
  end

  def execute(["adaptive" | _], _context) do
    {:update_config, %{thinking: "adaptive"}, "Thinking mode set to adaptive."}
  end

  def execute([mode | _], _context) do
    {:error,
     "Unknown thinking mode '#{mode}'. Available: #{Enum.join(Client.thinking_modes(), ", ")}"}
  end

  defp current_mode(%Config{thinking: mode}), do: mode
  defp current_mode(_), do: nil
end
