defmodule Viber.Commands.Handlers.Connect do
  @moduledoc """
  Handler for the /connect command.
  Connects to a named database or adds a new connection from a URL.
  """

  alias Viber.Database.ConnectionManager

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute([], _context) do
    case ConnectionManager.get_active() do
      {:ok, name, _repo} ->
        {:ok, "Active connection: #{name}"}

      {:error, _} ->
        {:error, "No active connection. Usage: /connect <name> or /connect <name> <url>"}
    end
  end

  def execute([name], context) do
    conns = ConnectionManager.list_connections()
    known = Enum.any?(conns, fn c -> c.name == name end)

    if known do
      connect_and_activate(name, context)
    else
      {:error,
       "Unknown connection '#{name}'. Use /connect #{name} <url> to add it, or /databases to list available connections."}
    end
  end

  def execute([name, url | _], context) do
    case ConnectionManager.add_connection_from_url(name, url) do
      :ok ->
        connect_and_activate(name, context)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp connect_and_activate(name, context) do
    case ConnectionManager.connect(name) do
      {:ok, _repo} ->
        session_id = context[:session_id]

        if session_id do
          ConnectionManager.set_active(name, session_id)
        else
          ConnectionManager.set_active(name)
        end

        {:ok, conn} = ConnectionManager.get_connection(name)
        ro = if conn.read_only, do: " (read-only)", else: ""

        {:ok,
         "Connected to '#{name}' (#{conn.type}://#{conn.hostname}:#{conn.port}/#{conn.database})#{ro}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
