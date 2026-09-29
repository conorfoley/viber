defmodule Viber.Runtime.Signature.Field do
  @moduledoc """
  One named, typed field of a `Viber.Runtime.Signature`.

  Field names stay strings: they come from signature text and model output
  and are never turned into atoms.
  """

  @type type ::
          :string
          | :integer
          | :number
          | :boolean
          | {:enum, [String.t()]}
          | {:list, type()}

  @type t :: %__MODULE__{
          name: String.t(),
          type: type(),
          description: String.t() | nil
        }

  @enforce_keys [:name, :type]
  defstruct [:name, :type, :description]
end
