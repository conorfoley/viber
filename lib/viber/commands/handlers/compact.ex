defmodule Viber.Commands.Handlers.Compact do
  @moduledoc """
  Handler for the /compact command.
  """

  alias Viber.Runtime.{Compact, Session}

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(_args, context) do
    session = context[:session]

    unless session do
      {:error, "No active session"}
    else
      before_count = length(Session.get_messages(session))

      case Compact.compact(session) do
        {:ok, removed} ->
          after_count = length(Session.get_messages(session))
          {:ok, "Compacted: #{before_count} → #{after_count} messages (#{removed} removed)"}

        {:error, reason} ->
          {:error, "Compaction failed: #{inspect(reason)}"}
      end
    end
  end
end
