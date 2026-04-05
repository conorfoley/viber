defmodule Viber.Tools.ExecutorTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Executor

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
end
