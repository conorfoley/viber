defmodule Viber.Tools.Result do
  @moduledoc """
  The normalized result of a tool call.

  Every call ends with exactly one `outcome`:

    * `:ok` — the call succeeded.
    * `:error` — the call ran and failed; nothing was applied.
    * `:refused` — refused before running (permissions, user denial,
      admission); repeating it is safe.
    * `:not_sent` — never reached its target (unknown tool, server not
      running); repeating it is safe.
    * `:unknown` — may have been applied; check state before retrying.
      Never retried automatically.
  """

  alias Viber.Runtime.Errors
  alias Viber.Tools.Failure

  @type outcome :: :ok | Failure.outcome()

  @type t :: %__MODULE__{
          output: String.t(),
          outcome: outcome(),
          reason: term()
        }

  @outcomes [:ok, :error, :refused, :not_sent, :unknown]

  @enforce_keys [:output, :outcome]
  defstruct [:output, :outcome, :reason]

  @spec outcomes() :: [outcome()]
  def outcomes, do: @outcomes

  @spec ok(String.t()) :: t()
  def ok(output) when is_binary(output), do: %__MODULE__{output: output, outcome: :ok}

  @spec failure(Failure.outcome(), String.t(), term()) :: t()
  def failure(outcome, message, reason \\ nil) when outcome in @outcomes and outcome != :ok do
    %__MODULE__{output: message, outcome: outcome, reason: reason}
  end

  @spec from_handler(term()) :: t()
  def from_handler({:ok, output}) when is_binary(output), do: ok(output)
  def from_handler({:ok, output}), do: ok(inspect(output))

  def from_handler({:error, %Failure{outcome: outcome, message: message, reason: reason}}),
    do: failure(outcome, message, reason)

  def from_handler({:error, reason}), do: failure(:error, Errors.message(reason), reason)
  def from_handler(other), do: failure(:error, "Tool returned an invalid result", other)

  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{outcome: :ok}), do: false
  def error?(%__MODULE__{}), do: true

  @spec model_output(t()) :: String.t()
  def model_output(%__MODULE__{outcome: :ok, output: output}), do: output

  def model_output(%__MODULE__{outcome: :unknown, output: output}) do
    "[outcome: unknown — the action may have been applied; check state before retrying]\n" <>
      output
  end

  def model_output(%__MODULE__{outcome: :refused, output: output}),
    do: "[outcome: refused — the action did not run]\n" <> output

  def model_output(%__MODULE__{outcome: :not_sent, output: output}),
    do: "[outcome: not_sent — the action did not reach its target]\n" <> output

  def model_output(%__MODULE__{output: output}), do: output

  @spec outcome_from_string(String.t() | atom() | nil) :: outcome() | nil
  def outcome_from_string(value) when value in @outcomes, do: value

  def outcome_from_string(value) when is_binary(value) do
    Enum.find(@outcomes, &(Atom.to_string(&1) == value))
  end

  def outcome_from_string(_), do: nil
end
