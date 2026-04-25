defmodule Viber.Commands.Handlers.Reload do
  @moduledoc """
  Handler for the /reload command.
  """

  use Viber.Commands.Handler

  alias Viber.HotReloader

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(_args, context) do
    project_root = context[:project_root] || File.cwd!()

    case HotReloader.reload(project_root) do
      {:ok, modules} ->
        names = Enum.map_join(modules, ", ", &inspect/1)
        count = length(modules)

        if count == 0 do
          {:ok, "No modules reloaded (nothing changed)."}
        else
          {:ok, "Recompiled #{count} module(s): #{names}"}
        end

      {:error, output} ->
        {:error, "Compilation failed:\n#{output}"}
    end
  end
end
