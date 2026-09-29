defmodule Viber.Tools.Executor do
  @moduledoc """
  Dispatches tool execution by name to the appropriate handler.

  `run/2` always returns a `Viber.Tools.Result`: handler returns are
  normalized, an unknown tool is `:not_sent`, and a crash is `:unknown` for
  a write (it may have been applied) or `:error` for a read.
  """

  alias Viber.Runtime.Errors
  alias Viber.Tools.{Registry, Result, Spec}

  @spec run(String.t(), map()) :: Result.t()
  def run(name, input) when is_map(input) do
    case Registry.get(Registry.normalize_name(name)) do
      {:ok, %Spec{handler: handler} = spec} when handler != nil ->
        invoke(spec, handler, input)

      {:ok, _} ->
        Result.failure(:not_sent, "Tool '#{name}' has no handler", :no_handler)

      :error ->
        Result.failure(:not_sent, "Unknown tool: #{name}", :unknown_tool)
    end
  end

  @spec execute(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(name, input) when is_map(input) do
    case run(name, input) do
      %Result{outcome: :ok, output: output} -> {:ok, output}
      %Result{output: output} -> {:error, output}
    end
  end

  @spec effect(String.t(), map()) :: Spec.effect()
  def effect(name, input) do
    case Registry.get(Registry.normalize_name(name)) do
      {:ok, %Spec{} = spec} -> Spec.effect(spec, input)
      :error -> :write
    end
  end

  @spec crash_result(Spec.effect(), term()) :: Result.t()
  def crash_result(:write, reason) do
    Result.failure(
      :unknown,
      "Tool execution crashed: #{Errors.message(reason)}",
      reason
    )
  end

  def crash_result(:read, reason) do
    Result.failure(:error, "Tool execution crashed: #{Errors.message(reason)}", reason)
  end

  defp invoke(spec, handler, input) do
    Result.from_handler(handler.(input))
  catch
    kind, value ->
      crash_result(Spec.effect(spec, input), Errors.from_caught(kind, value, __STACKTRACE__))
  end
end
