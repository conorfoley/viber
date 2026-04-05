defmodule Viber.API.InputMessage do
  @moduledoc """
  An input message in a conversation (user or assistant turn).
  """

  @type t :: %__MODULE__{
          role: String.t(),
          content: [map()]
        }

  @enforce_keys [:role, :content]
  defstruct [:role, :content]

  @spec user_text(String.t()) :: t()
  def user_text(text) do
    %__MODULE__{role: "user", content: [%{type: "text", text: text}]}
  end

  @spec user_tool_result(String.t(), String.t(), boolean()) :: t()
  def user_tool_result(tool_use_id, content, is_error) do
    result =
      %{type: "tool_result", tool_use_id: tool_use_id, content: [%{type: "text", text: content}]}

    result = if is_error, do: Map.put(result, :is_error, true), else: result
    %__MODULE__{role: "user", content: [result]}
  end
end

defimpl Jason.Encoder, for: Viber.API.InputMessage do
  def encode(msg, opts) do
    %{role: msg.role, content: msg.content}
    |> Jason.Encode.map(opts)
  end
end
