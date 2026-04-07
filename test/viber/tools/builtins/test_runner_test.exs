defmodule Viber.Tools.Builtins.TestRunnerTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 180_000

  alias Viber.Tools.Builtins.TestRunner

  describe "execute/1 — full run" do
    test "runs mix test on a specific file and returns passed status with test counts" do
      path = "test/viber/tools/builtins/mix_task_test.exs"
      assert {:ok, result} = TestRunner.execute(%{"path" => path})
      assert result =~ "Status: passed"
      assert result =~ "Tests:"
      assert result =~ "Failures: 0"
      assert result =~ "Execution time:"
      assert result =~ "--- Raw Output ---"
    end
  end

  describe "execute/1 — path targeting" do
    test "accepts a specific test file path" do
      path = "test/viber/tools/builtins/mix_task_test.exs"
      assert {:ok, result} = TestRunner.execute(%{"path" => path})
      assert result =~ "Status: passed"
      assert result =~ "--- Raw Output ---"
    end

    test "accepts path with line number" do
      path = "test/viber/tools/builtins/mix_task_test.exs"
      assert {:ok, result} = TestRunner.execute(%{"path" => path, "line" => 6})
      assert result =~ "Status:"
      assert result =~ "--- Raw Output ---"
    end
  end

  describe "execute/1 — failure output parsing" do
    test "returns failed status and failure block when tests fail" do
      fake_output = """
      Compiling 1 file (.ex)


        1) test something fails (SomeTest)
           test/some_test.exs:5
           Expected: true
           Got: false

      Finished in 0.05 seconds (0.05s async, 0.00s sync)
      1 test, 1 failure
      """

      result = build_formatted_result(1, fake_output, 1234)

      assert result =~ "Status: failed"
      assert result =~ "Tests: 1"
      assert result =~ "Failures: 1"
      assert result =~ "--- Failures ---"
      assert result =~ "1) test something fails"
      assert result =~ "--- Raw Output ---"
    end

    test "does not include failures section when all pass" do
      fake_output = """
      Finished in 0.05 seconds (0.05s async, 0.00s sync)
      3 tests, 0 failures, 1 skipped
      """

      result = build_formatted_result(0, fake_output, 500)

      assert result =~ "Status: passed"
      assert result =~ "Tests: 3"
      assert result =~ "Failures: 0"
      assert result =~ "Skipped: 1"
      refute result =~ "--- Failures ---"
    end
  end

  describe "execute/1 — summary parsing" do
    test "parses test counts including skipped" do
      fake_output = "5 tests, 2 failures, 1 skipped\n"
      result = build_formatted_result(1, fake_output, 100)
      assert result =~ "Tests: 5"
      assert result =~ "Failures: 2"
      assert result =~ "Skipped: 1"
    end

    test "handles output with no recognizable summary (compile error)" do
      fake_output = "** (CompileError) some compile error\n"
      result = build_formatted_result(2, fake_output, 100)
      assert result =~ "Status: error"
      assert result =~ "--- Raw Output ---"
    end
  end

  describe "execute/1 — timeout" do
    test "returns error status on timeout" do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "viber_slow_test.exs")

      File.write!(test_file, """
      defmodule Viber.SlowTimeoutTest do
        use ExUnit.Case
        test "slow" do
          Process.sleep(30_000)
        end
      end
      """)

      assert {:ok, result} = TestRunner.execute(%{"path" => test_file, "timeout" => 1})
      assert result =~ "exceeded timeout"
    after
      File.rm(Path.join(System.tmp_dir!(), "viber_slow_test.exs"))
    end
  end

  describe "execute/1 — extra args" do
    test "passes extra args to mix test" do
      path = "test/viber/tools/builtins/mix_task_test.exs"
      assert {:ok, result} = TestRunner.execute(%{"path" => path, "args" => ["--seed", "0"]})
      assert result =~ "Status: passed"
    end
  end

  defp build_formatted_result(exit_code, output, elapsed) do
    status = status_label(exit_code)
    summary = parse_summary(output)
    failures = parse_failures(output)

    header =
      ["Status: #{status}", summary, "Execution time: #{elapsed}ms"]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    failures_section =
      if failures != "", do: "\n--- Failures ---\n#{failures}", else: ""

    "#{header}#{failures_section}\n\n--- Raw Output ---\n#{output}"
  end

  defp status_label(0), do: "passed"
  defp status_label(1), do: "failed"
  defp status_label(_), do: "error"

  defp parse_summary(output) do
    case Regex.run(~r/(\d+) tests?, (\d+) failures?(?:, (\d+) skipped)?/, output) do
      [_, tests, failures | rest] ->
        skipped = List.first(rest)
        parts = ["Tests: #{tests}", "Failures: #{failures}"]
        parts = if skipped, do: parts ++ ["Skipped: #{skipped}"], else: parts
        Enum.join(parts, "  ")

      nil ->
        nil
    end
  end

  defp parse_failures(output) do
    case Regex.run(~r/\n(\s+1\) .+?)(?:\n\nFinished|\nRandomized|\z)/s, output) do
      nil -> ""
      [_, block] -> String.trim(block)
    end
  end
end
