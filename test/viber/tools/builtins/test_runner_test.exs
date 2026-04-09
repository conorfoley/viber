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
      tmp =
        Path.join([
          File.cwd!(),
          "test",
          "viber_synth_fail_#{:rand.uniform(1_000_000)}_test.exs"
        ])

      File.write!(tmp, """
      defmodule Viber.SynthFailTest do
        use ExUnit.Case
        test "intentional failure" do
          assert false, "synthetic failure"
        end
      end
      """)

      on_exit(fn -> File.rm(tmp) end)

      assert {:ok, result} = TestRunner.execute(%{"path" => tmp})
      assert result =~ "Status: failed"
      assert result =~ "Tests: 1"
      assert result =~ "Failures: 1"
      assert result =~ "--- Failures ---"
      assert result =~ "intentional failure"
      assert result =~ "--- Raw Output ---"
    end

    test "does not include failures section when all pass" do
      path = "test/viber/tools/builtins/mix_task_test.exs"
      assert {:ok, result} = TestRunner.execute(%{"path" => path})
      assert result =~ "Status: passed"
      assert result =~ "Failures: 0"
      refute result =~ "--- Failures ---"
    end
  end

  describe "execute/1 — summary parsing" do
    test "parses test counts including skipped" do
      tmp =
        Path.join([
          File.cwd!(),
          "test",
          "viber_synth_skip_#{:rand.uniform(1_000_000)}_test.exs"
        ])

      File.write!(tmp, """
      defmodule Viber.SynthSkipTest do
        use ExUnit.Case
        @tag :skip
        test "skipped test" do
          assert true
        end
        test "normal test" do
          assert true
        end
      end
      """)

      on_exit(fn -> File.rm(tmp) end)

      assert {:ok, result} = TestRunner.execute(%{"path" => tmp})
      assert result =~ "Tests: 2"
      assert result =~ "Failures: 0"
      assert result =~ "Skipped: 1"
    end

    test "handles compile error — status is non-passing, raw output included" do
      tmp =
        Path.join([
          File.cwd!(),
          "test",
          "viber_synth_compile_err_#{:rand.uniform(1_000_000)}_test.exs"
        ])

      File.write!(tmp, """
      this is not valid elixir !!!
      """)

      on_exit(fn -> File.rm(tmp) end)

      assert {:ok, result} = TestRunner.execute(%{"path" => tmp})
      refute result =~ "Status: passed"
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
end
