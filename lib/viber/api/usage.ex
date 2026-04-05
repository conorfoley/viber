defmodule Viber.API.Usage do
  @moduledoc """
  Token usage counters for an API response.
  """

  @type t :: %__MODULE__{
          input_tokens: non_neg_integer(),
          cache_creation_input_tokens: non_neg_integer(),
          cache_read_input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @enforce_keys [:input_tokens, :output_tokens]
  defstruct [
    :input_tokens,
    :output_tokens,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0
  ]

  @spec total_tokens(t()) :: non_neg_integer()
  def total_tokens(%__MODULE__{input_tokens: i, output_tokens: o}), do: i + o
end
