defmodule Viber.Commands.Handlers.Retry do
  @moduledoc """
  Handler for the /retry command. Re-sends the last user message after undoing the last turn.
  """

  use Viber.Commands.Handler

  alias Viber.Runtime.Session

  @spec execute([String.t()], map()) ::
          {:ok, String.t()} | {:error, String.t()} | {:retry, String.t()}
  def execute(_args, context) do
    session = context[:session]

    if session do
      case Session.pop_last_turn(session) do
        {:ok, last_input, _removed} -> {:retry, last_input}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "No active session"}
    end
  end
end
