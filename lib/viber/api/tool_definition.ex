defmodule Viber.API.ToolDefinition do
  @moduledoc """
  A tool definition for the LLM API.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          input_schema: map()
        }

  @enforce_keys [:name, :input_schema]
  defstruct [:name, :description, :input_schema]
end

defimpl Jason.Encoder, for: Viber.API.ToolDefinition do
  def encode(td, opts) do
    td
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> Jason.Encode.map(opts)
  end
end
