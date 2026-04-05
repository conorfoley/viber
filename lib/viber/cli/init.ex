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
      IO.puts("Initialized Viber project:")
      IO.puts("  Created #{viber_dir}/settings.json")
      IO.puts("  Created #{Path.join(project_root, "VIBER.md")}")

      if stack.language do
        IO.puts(
          "  Detected: #{stack.language}#{if stack.framework, do: " (#{stack.framework})", else: ""}"
        )
      end

      :ok
    end
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
