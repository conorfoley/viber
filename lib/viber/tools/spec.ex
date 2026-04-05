defmodule Viber.Tools.Spec do
  @moduledoc """
  Tool specification defining name, schema, description, and required permission.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          permission: Viber.Runtime.Permissions.permission_mode(),
          handler: (map() -> {:ok, String.t()} | {:error, String.t()}) | nil
        }

  @enforce_keys [:name, :description, :input_schema, :permission]
  defstruct [:name, :description, :input_schema, :permission, :handler]

  @spec to_tool_definition(t()) :: Viber.API.ToolDefinition.t()
  def to_tool_definition(%__MODULE__{} = spec) do
    %Viber.API.ToolDefinition{
      name: spec.name,
      description: spec.description,
      input_schema: spec.input_schema
    }
  end
end
