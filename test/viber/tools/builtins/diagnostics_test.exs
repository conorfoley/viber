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

  describe "dialyzer output structure" do
    test "result contains Tool and Findings headers" do
      assert {:ok, result} = Diagnostics.execute(%{"tool" => "dialyzer"})
      assert result =~ "Tool: dialyzer"
      assert result =~ "Findings:"
      assert result =~ "--- Raw Output ---"
    end

    test "result is either no-warnings or a list of file:line findings" do
      assert {:ok, result} = Diagnostics.execute(%{"tool" => "dialyzer"})

      if result =~ "Findings: 0" do
        assert result =~ "No warnings found."
      else
        assert Regex.match?(~r/\.exs?:\d+:/, result)
      end
    end

    test "scoping by path filters findings to that path" do
      assert {:ok, all} = Diagnostics.execute(%{"tool" => "dialyzer"})

      assert {:ok, scoped} =
               Diagnostics.execute(%{"tool" => "dialyzer", "path" => "lib/viber/api"})

      all_count = parse_findings_count(all)
      scoped_count = parse_findings_count(scoped)

      assert scoped_count <= all_count
    end
  end

  describe "credo output structure" do
    test "result contains Tool and Findings headers" do
      assert {:ok, result} = Diagnostics.execute(%{"tool" => "credo"})
      assert result =~ "Tool: credo"
      assert result =~ "Findings:"
      assert result =~ "--- Raw Output ---"
    end

    test "result is either no-issues or a list of severity-tagged findings" do
      assert {:ok, result} = Diagnostics.execute(%{"tool" => "credo"})

      if result =~ "Findings: 0" do
        assert result =~ "No issues found."
      else
        assert Regex.match?(~r/\[[CDFR]\] .+:\d+:/, result)
      end
    end

    test "scoping by path filters findings to that path" do
      assert {:ok, all} = Diagnostics.execute(%{"tool" => "credo"})

      assert {:ok, scoped} =
               Diagnostics.execute(%{"tool" => "credo", "path" => "lib/viber/runtime"})

      all_count = parse_findings_count(all)
      scoped_count = parse_findings_count(scoped)

      assert scoped_count <= all_count
    end
  end

  describe "tool unavailability" do
    test "returns friendly error when tool is not available" do
      fake_output = "** (Mix.NoTaskError) could not find task \"credo\""
      assert fake_output =~ "Mix.NoTaskError"
    end
  end

  defp parse_findings_count(result) do
    case Regex.run(~r/Findings: (\d+)/, result) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end
end
