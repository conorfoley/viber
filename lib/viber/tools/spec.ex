defmodule Viber.Tools.Spec do
  @moduledoc """
  Tool specification defining name, schema, description, and required permission.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          permission: Viber.Runtime.Permissions.permission_mode(),
          permission_fn: (map() -> Viber.Runtime.Permissions.permission_mode()) | nil,
          handler: (map() -> {:ok, String.t()} | {:error, String.t()}) | nil
        }

  @enforce_keys [:name, :description, :input_schema, :permission]
  defstruct [:name, :description, :input_schema, :permission, :permission_fn, :handler]

  @spec effective_permission(t(), map()) :: Viber.Runtime.Permissions.permission_mode()
  def effective_permission(%__MODULE__{permission_fn: nil, permission: perm}, _input), do: perm

  def effective_permission(%__MODULE__{permission_fn: fun}, input) when is_function(fun, 1),
    do: fun.(input)

  @spec to_tool_definition(t()) :: Viber.API.ToolDefinition.t()
  def to_tool_definition(%__MODULE__{} = spec) do
    %Viber.API.ToolDefinition{
      name: spec.name,
      description: spec.description,
      input_schema: spec.input_schema
    }
  end
end
