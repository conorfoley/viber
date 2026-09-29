defmodule Viber.Tools.Failure do
  @moduledoc """
  A tool failure that knows more than a string can say.

  Handlers may return `{:error, %Viber.Tools.Failure{}}` to declare the
  outcome of a failed call:

    * `:error` — the call ran and failed; nothing was applied.
    * `:refused` — the call was refused before it ran; repeating it is safe.
    * `:not_sent` — the call never reached its target; repeating it is safe.
    * `:unknown` — the call may have been applied (e.g. a write that timed
      out); state must be checked before retrying.

  `reason` keeps the underlying term; `message` is the text shown to the
  model and the user.
  """

  @type outcome :: :error | :refused | :not_sent | :unknown

  @type t :: %__MODULE__{
          outcome: outcome(),
          message: String.t(),
          reason: term()
        }

  @enforce_keys [:outcome, :message]
  defstruct [:outcome, :message, :reason]

  @spec new(outcome(), String.t(), term()) :: t()
  def new(outcome, message, reason \\ nil)
      when outcome in [:error, :refused, :not_sent, :unknown] and is_binary(message) do
    %__MODULE__{outcome: outcome, message: message, reason: reason}
  end
end
