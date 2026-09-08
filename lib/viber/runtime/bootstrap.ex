defmodule Viber.Runtime.Bootstrap do
  @moduledoc """
  Project stack detection from filesystem markers and startup credential checks.
  """

  @provider_env_vars [
    {"ANTHROPIC_API_KEY", "Anthropic Claude"},
    {"OPENAI_API_KEY", "OpenAI"},
    {"XAI_API_KEY", "xAI Grok"},
    {"OLLAMA_HOST", "Ollama (local)"}
  ]

  @spec check_provider_credentials(String.t()) :: :ok | {:warn, String.t()}
  def check_provider_credentials(model) do
    is_ollama = String.starts_with?(model, "ollama:")

    any_cloud_key =
      Enum.any?(["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "XAI_API_KEY"], &env_key_set?/1)

    ollama_host = env_key_set?("OLLAMA_HOST")

    cond do
      is_ollama && not ollama_host ->
        {:warn,
         "Model \"#{model}\" targets Ollama but OLLAMA_HOST is not set. " <>
           "Defaulting to http://localhost:11434 — set OLLAMA_HOST to override."}

      not is_ollama && not any_cloud_key && not ollama_host ->
        configured =
          @provider_env_vars
          |> Enum.map_join(", ", fn {var, label} -> "#{var} (#{label})" end)

        {:warn,
         "No LLM provider credentials detected. " <>
           "Set one of: #{configured}"}

      true ->
        :ok
    end
  end

  defp env_key_set?(var), do: Viber.Env.key_set?(var)

  @type stack_info :: %{
          language: String.t() | nil,
          framework: String.t() | nil,
          package_manager: String.t() | nil,
          test_command: String.t() | nil,
          lint_command: String.t() | nil
        }

  @spec detect_stack(String.t()) :: stack_info()
  def detect_stack(project_root) do
    [
      &detect_elixir_stack/1,
      &detect_rust_stack/1,
      &detect_node_stack_if_present/1,
      &detect_go_stack/1,
      &detect_python_stack/1,
      &detect_ruby_stack/1
    ]
    |> Enum.find_value(& &1.(project_root))
    |> Kernel.||(unknown_stack())
  end

  defp detect_elixir_stack(project_root) do
    if File.exists?(Path.join(project_root, "mix.exs")) do
      %{
        language: "Elixir",
        framework: "OTP",
        package_manager: "Mix/Hex",
        test_command: "mix test",
        lint_command: "mix compile --warnings-as-errors"
      }
    end
  end

  defp detect_rust_stack(project_root) do
    if File.exists?(Path.join(project_root, "Cargo.toml")) do
      %{
        language: "Rust",
        framework: nil,
        package_manager: "Cargo",
        test_command: "cargo test",
        lint_command: "cargo clippy"
      }
    end
  end

  defp detect_node_stack_if_present(project_root) do
    if File.exists?(Path.join(project_root, "package.json")) do
      detect_node_stack(project_root)
    end
  end

  defp detect_go_stack(project_root) do
    if File.exists?(Path.join(project_root, "go.mod")) do
      %{
        language: "Go",
        framework: nil,
        package_manager: "Go Modules",
        test_command: "go test ./...",
        lint_command: "go vet ./..."
      }
    end
  end

  defp detect_python_stack(project_root) do
    has_python =
      File.exists?(Path.join(project_root, "pyproject.toml")) or
        File.exists?(Path.join(project_root, "requirements.txt"))

    if has_python do
      %{
        language: "Python",
        framework: nil,
        package_manager: "pip",
        test_command: "pytest",
        lint_command: "ruff check"
      }
    end
  end

  defp detect_ruby_stack(project_root) do
    if File.exists?(Path.join(project_root, "Gemfile")) do
      %{
        language: "Ruby",
        framework: nil,
        package_manager: "Bundler",
        test_command: "bundle exec rspec",
        lint_command: "bundle exec rubocop"
      }
    end
  end

  defp unknown_stack do
    %{
      language: nil,
      framework: nil,
      package_manager: nil,
      test_command: nil,
      lint_command: nil
    }
  end

  defp detect_node_stack(project_root) do
    base = %{
      language: "JavaScript/TypeScript",
      framework: nil,
      package_manager: "npm",
      test_command: "npm test",
      lint_command: "npm run lint"
    }

    with {:ok, content} <- File.read(Path.join(project_root, "package.json")),
         {:ok, pkg} <- Jason.decode(content) do
      %{base | framework: detect_node_framework(pkg)}
    else
      _ -> base
    end
  end

  defp detect_node_framework(pkg) do
    deps = Map.merge(pkg["dependencies"] || %{}, pkg["devDependencies"] || %{})

    cond do
      Map.has_key?(deps, "next") -> "Next.js"
      Map.has_key?(deps, "react") -> "React"
      Map.has_key?(deps, "vue") -> "Vue"
      Map.has_key?(deps, "express") -> "Express"
      true -> nil
    end
  end
end
