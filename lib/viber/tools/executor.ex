defmodule Viber.Tools.Executor do
  @moduledoc """
  Dispatches tool execution by name to the appropriate handler.
  """

  alias Viber.Tools.Registry

  @spec execute(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(name, input) when is_map(input) do
    case Registry.get(Registry.normalize_name(name)) do
      {:ok, %{handler: handler}} when handler != nil -> handler.(input)
      {:ok, _} -> {:error, "Tool '#{name}' has no handler"}
      :error -> {:error, "Unknown tool: #{name}"}
    end
  end
end
