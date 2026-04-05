defmodule Viber.Runtime.Usage do
  @moduledoc """
  Token usage tracking and aggregation across conversation turns.
  """

  @type t :: %__MODULE__{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cache_creation_tokens: non_neg_integer(),
          cache_read_tokens: non_neg_integer(),
          turns: non_neg_integer()
        }

  defstruct input_tokens: 0,
            output_tokens: 0,
            cache_creation_tokens: 0,
            cache_read_tokens: 0,
            turns: 0

  @spec add(t(), t()) :: t()
  def add(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      input_tokens: a.input_tokens + b.input_tokens,
      output_tokens: a.output_tokens + b.output_tokens,
      cache_creation_tokens: a.cache_creation_tokens + b.cache_creation_tokens,
      cache_read_tokens: a.cache_read_tokens + b.cache_read_tokens,
      turns: a.turns + b.turns
    }
  end

  @spec from_api_usage(Viber.API.Usage.t()) :: t()
  def from_api_usage(%Viber.API.Usage{} = api) do
    %__MODULE__{
      input_tokens: api.input_tokens,
      output_tokens: api.output_tokens,
      cache_creation_tokens: api.cache_creation_input_tokens,
      cache_read_tokens: api.cache_read_input_tokens,
      turns: 1
    }
  end

  @spec total_tokens(t()) :: non_neg_integer()
  def total_tokens(%__MODULE__{} = u) do
    u.input_tokens + u.output_tokens + u.cache_creation_tokens + u.cache_read_tokens
  end

  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = u) do
    "In: #{format_number(u.input_tokens)} | Out: #{format_number(u.output_tokens)} | Total: #{format_number(total_tokens(u))}"
  end

  defp format_number(n) when n >= 1_000 do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.reverse/1)
    |> String.reverse()
    |> String.replace(~r/^,/, "")
  end

  defp format_number(n), do: Integer.to_string(n)
end
