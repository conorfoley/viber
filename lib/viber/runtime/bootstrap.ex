defmodule Viber.Runtime.Bootstrap do
  @moduledoc """
  Project stack detection from filesystem markers.
  """

  @type stack_info :: %{
          language: String.t() | nil,
          framework: String.t() | nil,
          package_manager: String.t() | nil,
          test_command: String.t() | nil,
          lint_command: String.t() | nil
        }

  @spec detect_stack(String.t()) :: stack_info()
  def detect_stack(project_root) do
    cond do
      File.exists?(Path.join(project_root, "mix.exs")) ->
        %{
          language: "Elixir",
          framework: "OTP",
          package_manager: "Mix/Hex",
          test_command: "mix test",
          lint_command: "mix compile --warnings-as-errors"
        }

      File.exists?(Path.join(project_root, "Cargo.toml")) ->
        %{
          language: "Rust",
          framework: nil,
          package_manager: "Cargo",
          test_command: "cargo test",
          lint_command: "cargo clippy"
        }

      File.exists?(Path.join(project_root, "package.json")) ->
        detect_node_stack(project_root)

      File.exists?(Path.join(project_root, "go.mod")) ->
        %{
          language: "Go",
          framework: nil,
          package_manager: "Go Modules",
          test_command: "go test ./...",
          lint_command: "go vet ./..."
        }

      File.exists?(Path.join(project_root, "pyproject.toml")) or
          File.exists?(Path.join(project_root, "requirements.txt")) ->
        %{
          language: "Python",
          framework: nil,
          package_manager: "pip",
          test_command: "pytest",
          lint_command: "ruff check"
        }

      File.exists?(Path.join(project_root, "Gemfile")) ->
        %{
          language: "Ruby",
          framework: nil,
          package_manager: "Bundler",
          test_command: "bundle exec rspec",
          lint_command: "bundle exec rubocop"
        }

      true ->
        %{
          language: nil,
          framework: nil,
          package_manager: nil,
          test_command: nil,
          lint_command: nil
        }
    end
  end

  defp detect_node_stack(project_root) do
    base = %{
      language: "JavaScript/TypeScript",
      framework: nil,
      package_manager: "npm",
      test_command: "npm test",
      lint_command: "npm run lint"
    }

    case File.read(Path.join(project_root, "package.json")) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, pkg} ->
            deps = Map.merge(pkg["dependencies"] || %{}, pkg["devDependencies"] || %{})

            framework =
              cond do
                Map.has_key?(deps, "next") -> "Next.js"
                Map.has_key?(deps, "react") -> "React"
                Map.has_key?(deps, "vue") -> "Vue"
                Map.has_key?(deps, "express") -> "Express"
                true -> nil
              end

            %{base | framework: framework}

          _ ->
            base
        end

      _ ->
        base
    end
  end
end
