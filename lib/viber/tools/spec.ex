defmodule Viber.Tools.Spec do
  @moduledoc """
  Tool specification defining name, schema, description, and required permission.

  `effect/2` says whether a call may change the world. It decides how a
  crash or timeout is classified: a `:write` that dies mid-flight has an
  `:unknown` outcome, a `:read` is a plain `:error`. By default a call is a
  `:write` unless its effective permission is `:read_only`; set `effect_fn`
  to override.
  """

  @type effect :: :read | :write

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          permission: Viber.Runtime.Permissions.permission_mode(),
          permission_fn: (map() -> Viber.Runtime.Permissions.permission_mode()) | nil,
          effect_fn: (map() -> effect()) | nil,
          handler: (map() -> {:ok, String.t()} | {:error, term()}) | nil,
          toolset: atom(),
          concurrent: boolean()
        }

  @enforce_keys [:name, :description, :input_schema, :permission]
  defstruct [
    :name,
    :description,
    :input_schema,
    :permission,
    :permission_fn,
    :effect_fn,
    :handler,
    toolset: :core,
    concurrent: true
  ]

  @spec effective_permission(t(), map()) :: Viber.Runtime.Permissions.permission_mode()
  def effective_permission(%__MODULE__{permission_fn: nil, permission: perm}, _input), do: perm

  def effective_permission(%__MODULE__{permission_fn: fun}, input) when is_function(fun, 1),
    do: fun.(input)

  @spec effect(t(), map()) :: effect()
  def effect(%__MODULE__{effect_fn: fun}, input) when is_function(fun, 1), do: fun.(input)

  def effect(%__MODULE__{} = spec, input) do
    if effective_permission(spec, input) == :read_only, do: :read, else: :write
  end

  @spec to_tool_definition(t()) :: Viber.API.ToolDefinition.t()
  def to_tool_definition(%__MODULE__{} = spec) do
    %Viber.API.ToolDefinition{
      name: spec.name,
      description: spec.description,
      input_schema: spec.input_schema
    }
  end
end
