defmodule Viber.Tools.Builtins.MixTaskTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.MixTask

  test "successful task returns exit code 0 and output" do
    assert {:ok, result} = MixTask.execute(%{"task" => "help"})
    assert result =~ "Exit code: 0"
    assert result =~ "Execution time:"
  end

  test "task with args is passed through" do
    assert {:ok, result} = MixTask.execute(%{"task" => "help", "args" => ["help"]})
    assert result =~ "Exit code: 0"
  end

  test "non-zero exit code is captured" do
    assert {:ok, result} = MixTask.execute(%{"task" => "does_not_exist_xyz"})

    exit_code =
      result |> String.split("\n") |> hd() |> String.replace("Exit code: ", "") |> String.trim()

    assert exit_code != "0"
  end

  test "timeout returns timeout result" do
    assert {:ok, result} =
             MixTask.execute(%{
               "task" => "run",
               "args" => ["--eval", "Process.sleep(10_000)"],
               "timeout" => 1
             })

    assert result =~ "Exit code: timeout"
    assert result =~ "Task exceeded timeout"
  end

  test "missing task param returns error" do
    assert {:error, msg} = MixTask.execute(%{})
    assert msg =~ "task"
  end

  test "missing task param with other keys returns error" do
    assert {:error, _} = MixTask.execute(%{"args" => ["--help"]})
  end
end
