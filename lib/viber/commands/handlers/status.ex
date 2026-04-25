defmodule Viber.Commands.Handlers.Status do
  @moduledoc """
  Handler for the /status command.
  """

  use Viber.Commands.Handler

  alias Viber.Runtime.{Permissions, Session, Usage}

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(_args, context) do
    session = context[:session]
    model = context[:model] || "unknown"
    permission_mode = context[:permission_mode] || :prompt

    messages = if session, do: Session.get_messages(session), else: []
    usage = if session, do: Session.get_usage(session), else: %Usage{}

    lines = [
      "Model: #{model}",
      "Permission mode: #{Permissions.mode_to_string(permission_mode)}",
      "Messages: #{length(messages)}",
      "Usage: #{Usage.format(usage)}"
    ]

    mcp_servers = context[:mcp_servers]

    lines =
      if mcp_servers && map_size(mcp_servers) > 0 do
        names = Map.keys(mcp_servers) |> Enum.join(", ")
        lines ++ ["MCP servers: #{names}"]
      else
        lines
      end

    {:ok, Enum.join(lines, "\n")}
  end
end
