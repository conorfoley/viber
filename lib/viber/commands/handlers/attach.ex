defmodule Viber.Commands.Handlers.Attach do
  @moduledoc """
  Handler for the /attach command.
  """

  alias Viber.Runtime.{FileRefs, Session}

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute([], _context) do
    {:error, "Usage: /attach <path|glob> [...]"}
  end

  def execute(args, context) do
    session = context[:session]

    unless session do
      {:error, "No active session"}
    else
      project_root = context[:project_root] || File.cwd!()

      results =
        args
        |> Enum.flat_map(&FileRefs.resolve_pattern(&1, project_root))

      {combined, errors} = FileRefs.format_results(results)

      if combined == "" do
        {:error, Enum.join(errors, "\n")}
      else
        ok_paths =
          results
          |> Enum.filter(fn {tag, _, _} -> tag == :ok end)
          |> Enum.map(fn {:ok, path, _} -> path end)

        message = %{role: :user, blocks: [{:text, combined}], usage: nil}
        :ok = Session.add_message(session, message)

        count = length(ok_paths)
        paths_str = Enum.join(ok_paths, ", ")
        summary = "Attached #{count} file(s): #{paths_str}"

        if errors == [] do
          {:ok, summary}
        else
          {:ok, summary <> "\n" <> Enum.join(errors, "\n")}
        end
      end
    end
  end
end
