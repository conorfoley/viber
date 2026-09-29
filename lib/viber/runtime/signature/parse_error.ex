defmodule Viber.Runtime.Signature.ParseError do
  @moduledoc """
  A model reply that does not fit its signature.

  `kind` is one of:

    * `:malformed` — the reply is not a JSON object.
    * `:missing_fields` — required output fields are absent (`fields`).
    * `:invalid_fields` — fields are present but have the wrong type or an
      enum value outside the allowed set (`fields`).
    * `:no_tool_call` — the model did not call the submit tool and its text
      held no JSON object.

  `raw` keeps what the model actually returned.
  """

  @type kind :: :malformed | :missing_fields | :invalid_fields | :no_tool_call

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          fields: [String.t()],
          raw: term()
        }

  defexception [:kind, :message, fields: [], raw: nil]

  @spec new(kind(), String.t(), keyword()) :: t()
  def new(kind, message, opts \\ []) do
    %__MODULE__{
      kind: kind,
      message: message,
      fields: Keyword.get(opts, :fields, []),
      raw: Keyword.get(opts, :raw)
    }
  end
end
