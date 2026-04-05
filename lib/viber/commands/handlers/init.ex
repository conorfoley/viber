defmodule Viber.Commands.Handlers.Init do
  @moduledoc """
  Handler for the /init command.
  """

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(_args, _context) do
    {:ok, "Run 'viber init' from the command line to initialize this project."}
  end
end
