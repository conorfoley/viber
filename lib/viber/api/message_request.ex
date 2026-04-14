defmodule Viber.API.MessageRequest do
  @moduledoc """
  A request to the LLM messages API.
  """

  @type t :: %__MODULE__{
          model: String.t(),
          max_tokens: pos_integer() | nil,
          messages: [Viber.API.InputMessage.t()],
          system: String.t() | nil,
          tools: [Viber.API.ToolDefinition.t()] | nil,
          tool_choice: atom() | {:tool, String.t()} | nil,
          stream: boolean(),
          provider_overrides: map()
        }

  @enforce_keys [:model, :messages]
  defstruct [
    :model,
    :max_tokens,
    :messages,
    :system,
    :tools,
    :tool_choice,
    stream: false,
    provider_overrides: %{}
  ]

  @spec with_streaming(t()) :: t()
  def with_streaming(%__MODULE__{} = req), do: %{req | stream: true}
end

defimpl Jason.Encoder, for: Viber.API.MessageRequest do
  def encode(req, opts) do
    map = %{model: req.model, max_tokens: req.max_tokens, messages: req.messages}

    map = if req.system, do: Map.put(map, :system, req.system), else: map
    map = if req.tools, do: Map.put(map, :tools, req.tools), else: map
    map = if req.stream, do: Map.put(map, :stream, true), else: map

    map =
      if req.tool_choice do
        Map.put(map, :tool_choice, encode_tool_choice(req.tool_choice))
      else
        map
      end

    Jason.Encode.map(map, opts)
  end

  defp encode_tool_choice(:auto), do: %{type: "auto"}
  defp encode_tool_choice(:any), do: %{type: "any"}
  defp encode_tool_choice({:tool, name}), do: %{type: "tool", name: name}
end
