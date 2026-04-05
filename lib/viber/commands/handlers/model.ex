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

  def execute([new_model | _], _context) do
    resolved = Client.resolve_model_alias(new_model)

    if new_model == resolved do
      {:ok, "Switched to model: #{new_model}"}
    else
      {:ok, "Switched to model: #{new_model} (#{resolved})"}
    end
  end
end
