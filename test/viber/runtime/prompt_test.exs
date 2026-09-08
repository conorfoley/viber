defmodule Viber.Runtime.PromptTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.{Bootstrap, Prompt}

  describe "build/1" do
    test "produces a valid prompt string with default options" do
      prompt = Prompt.build(project_root: System.tmp_dir!())
      assert is_binary(prompt)
      assert prompt =~ "Viber"
      assert prompt =~ "# Environment"
      assert prompt =~ "# Available Tools"
      assert prompt =~ "# Permission Mode"
    end

    test "environment section contains OS info" do
      prompt = Prompt.build(project_root: System.tmp_dir!())
      assert prompt =~ "Platform:"
      assert prompt =~ "Working directory:"
      assert prompt =~ "Date:"
    end

    @tag :tmp_dir
    test "includes VIBER.md content when present", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "VIBER.md"), "Always use tabs for indentation.")
      prompt = Prompt.build(project_root: tmp_dir)
      assert prompt =~ "Always use tabs for indentation."
      assert prompt =~ "Project Instructions"
    end

    @tag :tmp_dir
    test "lists installed skills with load instructions", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join([tmp_dir, ".viber", "skills", "demo"])
      File.mkdir_p!(skill_dir)

      File.write!(
        Path.join(skill_dir, "SKILL.md"),
        "---\nname: demo\ndescription: Demo skill\n---\nbody"
      )

      prompt = Prompt.build(project_root: tmp_dir)
      assert prompt =~ "# Skills"
      assert prompt =~ "demo: Demo skill"
      assert prompt =~ "`skill` tool"
    end

    test "omits skills section when no skills installed" do
      prompt = Prompt.build(project_root: System.tmp_dir!())
      refute prompt =~ "# Skills"
    end

    test "custom instructions appear in prompt" do
      prompt = Prompt.build(project_root: System.tmp_dir!(), custom_instructions: "Be concise.")
      assert prompt =~ "# Custom Instructions"
      assert prompt =~ "Be concise."
    end

    test "permission mode appears in prompt" do
      prompt = Prompt.build(project_root: System.tmp_dir!(), permission_mode: :read_only)
      assert prompt =~ "read-only"
      assert prompt =~ "No modifications allowed"
    end

    test "browser_context nil omits section" do
      prompt = Prompt.build(project_root: System.tmp_dir!(), browser_context: nil)
      refute prompt =~ "Browser Context"
    end

    test "browser_context struct renders section" do
      ctx = %Viber.Runtime.BrowserContext{url: "https://example.com", title: "Example"}
      prompt = Prompt.build(project_root: System.tmp_dir!(), browser_context: ctx)
      assert prompt =~ "# Browser Context"
      assert prompt =~ "URL: https://example.com"
      assert prompt =~ "Title: Example"
    end

    test "browser_context raw map gets coerced" do
      prompt =
        Prompt.build(
          project_root: System.tmp_dir!(),
          browser_context: %{"url" => "https://example.com"}
        )

      assert prompt =~ "# Browser Context"
      assert prompt =~ "URL: https://example.com"
    end
  end

  describe "Bootstrap.detect_stack/1" do
    test "identifies Elixir project" do
      stack = Bootstrap.detect_stack(File.cwd!())
      assert stack.language == "Elixir"
      assert stack.test_command == "mix test"
    end

    @tag :tmp_dir
    test "returns nil fields for unknown project", %{tmp_dir: tmp_dir} do
      stack = Bootstrap.detect_stack(tmp_dir)
      assert stack.language == nil
    end
  end
end
