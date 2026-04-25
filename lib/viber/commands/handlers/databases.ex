defmodule Viber.Commands.Handlers.Databases do
  @moduledoc """
  Handler for the /databases command.
  Lists configured database connections with their status.
  """

  use Viber.Commands.Handler

  alias Viber.Database.ConnectionManager

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(["test", name | _], _context) do
    ConnectionManager.test_connection(name)
  end

  def execute(["remove", name | _], _context) do
    case ConnectionManager.remove_connection(name) do
      :ok -> {:ok, "Removed connection '#{name}'"}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(_args, _context) do
    conns = ConnectionManager.list_connections()

    if conns == [] do
      {:ok,
       "No database connections configured.\nAdd one with: /connect <name> <url>\nOr create ~/.viber/databases.exs"}
    else
      active_name =
        case ConnectionManager.get_active() do
          {:ok, name, _} -> name
          _ -> nil
        end

      lines =
        Enum.map(conns, fn conn ->
          status = if conn[:connected], do: "connected", else: "disconnected"
          ro = if conn.read_only, do: " [read-only]", else: ""
          active = if conn.name == active_name, do: " ← active", else: ""

          "  #{conn.name} | #{conn.type}://#{conn.hostname}:#{conn.port}/#{conn.database} | #{status}#{ro}#{active}"
        end)

      header = "Database connections:"
      {:ok, Enum.join([header | lines], "\n")}
    end
  end
end
