defmodule Mix.Tasks.Viber do
  @moduledoc "Start the Viber interactive REPL."
  @shortdoc "Start the Viber interactive REPL"

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start", [])
    Viber.CLI.Main.main(args)
  end
end
