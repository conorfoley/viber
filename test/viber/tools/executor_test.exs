defmodule Viber.Tools.ExecutorTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.{Executor, Result}

  test "dispatches to correct handler" do
    assert {:ok, result} = Executor.execute("bash", %{"command" => "echo hello"})
    assert result =~ "hello"
    assert result =~ "Exit code: 0"
  end

  test "unknown tool returns error" do
    assert {:error, "Unknown tool: nonexistent"} = Executor.execute("nonexistent", %{})
  end

  test "normalizes tool name before dispatch" do
    assert {:ok, result} = Executor.execute("Bash", %{"command" => "echo test"})
    assert result =~ "test"
  end

  describe "run/2" do
    test "success is :ok" do
      assert %Result{outcome: :ok, output: out} = Executor.run("bash", %{"command" => "echo hi"})
      assert out =~ "hi"
    end

    test "unknown tool is :not_sent" do
      assert %Result{outcome: :not_sent, reason: :unknown_tool} = Executor.run("nonexistent", %{})
    end
  end

  describe "crash_result/2" do
    test "a crashed write is :unknown" do
      assert %Result{outcome: :unknown, output: "Tool execution crashed: " <> _} =
               Executor.crash_result(:write, %RuntimeError{message: "boom"})
    end

    test "a crashed read is :error" do
      assert %Result{outcome: :error, reason: {:exit, :killed}} =
               Executor.crash_result(:read, {:exit, :killed})
    end
  end

  describe "effect/2" do
    test "read-only tools are reads" do
      assert Executor.effect("read_file", %{"path" => "x"}) == :read
    end

    test "git classifies by subcommand" do
      assert Executor.effect("git", %{"subcommand" => "status"}) == :read
      assert Executor.effect("git", %{"subcommand" => "commit"}) == :write
    end

    test "unknown tools are treated as writes" do
      assert Executor.effect("nonexistent", %{}) == :write
    end
  end
end
