defmodule Viber.Commands.Handlers.Clear do
  @moduledoc """
  Handler for the /clear command.
  """

  use Viber.Commands.Handler

  alias Viber.Runtime.Session

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(_args, context) do
    session = context[:session]

    unless session do
      {:error, "No active session"}
    else
      :ok = Session.clear(session)
      {:ok, "Session cleared."}
    end
  end
end
