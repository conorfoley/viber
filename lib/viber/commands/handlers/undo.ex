defmodule Viber.Commands.Handlers.Undo do
  @moduledoc """
  Handler for the /undo command. Removes the last user turn and all subsequent messages.
  """

  use Viber.Commands.Handler

  alias Viber.Runtime.Session

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(_args, context) do
    session = context[:session]

    if session do
      case Session.undo_last_turn(session) do
        {:ok, removed} ->
          {:ok, "Undid last turn (removed #{removed} message(s))."}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "No active session"}
    end
  end
end
