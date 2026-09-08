defmodule Viber.CLI.Init do
  @moduledoc """
  Project initialization flow — creates .viber/ config and VIBER.md.
  """

  alias Viber.Runtime.Bootstrap

  @spec run(String.t()) :: :ok | {:error, term()}
  def run(project_root) do
    stack = Bootstrap.detect_stack(project_root)
    viber_dir = Path.join(project_root, ".viber")

    with :ok <- File.mkdir_p(viber_dir),
         :ok <- write_settings(viber_dir, stack),
         :ok <- write_viber_md(project_root, stack) do
      print_init_success(viber_dir, project_root)
      print_detected_stack(stack)

      :ok
    end
  end

  defp print_init_success(viber_dir, project_root) do
    IO.puts([
      IO.ANSI.green(),
      IO.ANSI.bright(),
      "✔ ",
      IO.ANSI.reset(),
      "Initialized Viber project"
    ])

    IO.puts([
      IO.ANSI.faint(),
      "  Created ",
      IO.ANSI.reset(),
      IO.ANSI.cyan(),
      "#{viber_dir}/settings.json",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.faint(),
      "  Created ",
      IO.ANSI.reset(),
      IO.ANSI.cyan(),
      "#{Path.join(project_root, "VIBER.md")}",
      IO.ANSI.reset()
    ])
  end

  defp print_detected_stack(%{language: nil}), do: :ok

  defp print_detected_stack(%{language: lang, framework: framework}) do
    fw = framework_suffix(framework)

    IO.puts([
      IO.ANSI.faint(),
      "  Detected ",
      IO.ANSI.reset(),
      IO.ANSI.bright(),
      lang,
      IO.ANSI.reset() | fw
    ])
  end

  defp framework_suffix(nil), do: []

  defp framework_suffix(framework) do
    [IO.ANSI.faint(), " (", IO.ANSI.reset(), framework, IO.ANSI.faint(), ")"]
  end

  defp write_settings(viber_dir, _stack) do
    settings = %{
      "model" => "sonnet",
      "permissions" => %{"allow" => "workspace-write"}
    }

    path = Path.join(viber_dir, "settings.json")

    if File.exists?(path) do
      IO.puts("  #{path} already exists, skipping")
      :ok
    else
      File.write(path, Jason.encode!(settings, pretty: true))
    end
  end

  defp write_viber_md(project_root, stack) do
    path = Path.join(project_root, "VIBER.md")

    if File.exists?(path) do
      IO.puts("  #{path} already exists, skipping")
      :ok
    else
      content = viber_md_template(stack)
      File.write(path, content)
    end
  end

  defp viber_md_template(stack) do
    lang_line = if stack.language, do: "- Language: #{stack.language}\n", else: ""
    fw_line = if stack.framework, do: "- Framework: #{stack.framework}\n", else: ""

    """
    # Project Instructions

    ## Overview
    [Describe your project here]

    ## Stack
    #{lang_line}#{fw_line}
    ## Conventions
    [Add project-specific conventions, patterns, or rules here]

    ## Key Files
    [List important files or directories the AI should know about]
    """
  end
end
