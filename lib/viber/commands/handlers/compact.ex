defmodule Viber.Commands.Handlers.Compact do
  @moduledoc """
  Handler for the /compact command.
  """

  use Viber.Commands.Handler

  alias Viber.Runtime.{Compact, Session}

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(_args, context) do
    session = context[:session]

    unless session do
      {:error, "No active session"}
    else
      before_count = length(Session.get_messages(session))

      {:ok, removed} = Compact.compact(session)
      after_count = length(Session.get_messages(session))
      {:ok, "Compacted: #{before_count} → #{after_count} messages (#{removed} removed)"}
    end
  end
end
