defmodule Viber.Tools.Builtins.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.Diagnostics

  describe "execute/1 — parameter validation" do
    test "missing tool param returns error" do
      assert {:error, msg} = Diagnostics.execute(%{})
      assert msg =~ "tool"
    end

    test "unknown tool returns error" do
      assert {:error, msg} = Diagnostics.execute(%{"tool" => "rubocop"})
      assert msg =~ "Unknown tool"
      assert msg =~ "rubocop"
    end

    test "non-map input returns error" do
      assert {:error, _} = Diagnostics.execute(nil)
    end
  end

  describe "dialyzer output parsing" do
    test "parses dialyzer findings from known output" do
      fake_output = """
      lib/viber/tools/registry.ex:42: Function foo/1 does not exist.
      lib/viber/runtime/session.ex:87: The pattern can never match.
      """

      result = build_dialyzer_result(fake_output)

      assert result =~ "Tool: dialyzer"
      assert result =~ "Findings: 2"
      assert result =~ "lib/viber/tools/registry.ex:42:"
      assert result =~ "lib/viber/runtime/session.ex:87:"
      assert result =~ "--- Raw Output ---"
    end

    test "returns zero findings when no matching lines" do
      fake_output = "Updating PLT...\nNo warnings\n"

      result = build_dialyzer_result(fake_output)

      assert result =~ "Tool: dialyzer"
      assert result =~ "Findings: 0"
      assert result =~ "No warnings found."
      assert result =~ "--- Raw Output ---"
    end

    test "parses .exs files as well as .ex files" do
      fake_output = "test/support/mock_provider.exs:10: Contract violation.\n"

      result = build_dialyzer_result(fake_output)

      assert result =~ "Findings: 1"
      assert result =~ "test/support/mock_provider.exs:10:"
    end
  end

  describe "credo output parsing" do
    test "parses credo findings from known output" do
      fake_output = """
      [C] › lib/viber/tools/registry.ex:42:5 Credo.Check.Refactor.Nesting: Nesting of 4 detected.
      [R] › lib/viber/runtime/session.ex:10:1 Credo.Check.Readability.ModuleDoc: Modules should have a @moduledoc tag.
      """

      result = build_credo_result(fake_output)

      assert result =~ "Tool: credo"
      assert result =~ "Findings: 2"
      assert result =~ "[C] lib/viber/tools/registry.ex:42:"
      assert result =~ "[R] lib/viber/runtime/session.ex:10:"
      assert result =~ "--- Raw Output ---"
    end

    test "returns zero findings when no matching lines" do
      fake_output = "All good! No issues found.\n"

      result = build_credo_result(fake_output)

      assert result =~ "Tool: credo"
      assert result =~ "Findings: 0"
      assert result =~ "No issues found."
    end

    test "parses all severity levels C, D, F, R" do
      fake_output = """
      [C] › lib/a.ex:1:1 CheckC: consistency issue.
      [D] › lib/b.ex:2:1 CheckD: design issue.
      [F] › lib/c.ex:3:1 CheckF: formatter issue.
      [R] › lib/d.ex:4:1 CheckR: readability issue.
      """

      result = build_credo_result(fake_output)

      assert result =~ "Findings: 4"
      assert result =~ "[C] lib/a.ex:1:"
      assert result =~ "[D] lib/b.ex:2:"
      assert result =~ "[F] lib/c.ex:3:"
      assert result =~ "[R] lib/d.ex:4:"
    end
  end

  describe "tool unavailability" do
    test "returns friendly error when tool is not available" do
      fake_output = "** (Mix.NoTaskError) could not find task \"credo\""

      result = build_credo_result(fake_output)

      assert result =~ "is not available" or result =~ "No issues found."
    end
  end

  defp build_dialyzer_result(raw_output) do
    findings = parse_dialyzer(raw_output)
    format_dialyzer(findings, raw_output)
  end

  defp build_credo_result(raw_output) do
    findings = parse_credo(raw_output)
    format_credo(findings, raw_output)
  end

  defp parse_dialyzer(output) do
    output
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/(.+\.exs?):(\d+):(.*)/, String.trim(line)) do
        [_, file, line_num, message] -> [{file, line_num, String.trim(message)}]
        _ -> []
      end
    end)
  end

  defp parse_credo(output) do
    output
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/\[([CDFR])\] ›\s+(.+):(\d+):\d+\s+(.*)/, line) do
        [_, severity, file, line_num, message] ->
          [{severity, file, line_num, String.trim(message)}]

        _ ->
          []
      end
    end)
  end

  defp format_dialyzer(findings, raw_output) do
    count = length(findings)

    body =
      if count == 0 do
        "No warnings found."
      else
        findings
        |> Enum.map(fn {file, line, message} -> "#{file}:#{line}: #{message}" end)
        |> Enum.join("\n")
      end

    "Tool: dialyzer\nFindings: #{count}\n\n#{body}\n\n--- Raw Output ---\n#{raw_output}"
  end

  defp format_credo(findings, raw_output) do
    count = length(findings)

    body =
      if count == 0 do
        "No issues found."
      else
        findings
        |> Enum.map(fn {severity, file, line, message} ->
          "[#{severity}] #{file}:#{line}: #{message}"
        end)
        |> Enum.join("\n")
      end

    "Tool: credo\nFindings: #{count}\n\n#{body}\n\n--- Raw Output ---\n#{raw_output}"
  end
end
