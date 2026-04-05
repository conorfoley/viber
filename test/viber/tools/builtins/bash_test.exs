defmodule Viber.Tools.Builtins.BashTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.Bash

  test "simple echo command" do
    assert {:ok, result} = Bash.execute(%{"command" => "echo hello world"})
    assert result =~ "hello world"
    assert result =~ "Exit code: 0"
  end

  test "captures non-zero exit code" do
    assert {:ok, result} = Bash.execute(%{"command" => "exit 42"})
    assert result =~ "Exit code: 42"
  end

  test "captures stderr merged with stdout" do
    assert {:ok, result} = Bash.execute(%{"command" => "echo err >&2"})
    assert result =~ "err"
  end

  test "missing command returns error" do
    assert {:error, _} = Bash.execute(%{})
  end
end
