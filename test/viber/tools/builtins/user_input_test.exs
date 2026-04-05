defmodule Viber.Tools.Builtins.UserInputTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.UserInput

  test "returns user response from stdin" do
    {:ok, io} = StringIO.open("blue\n")
    original_gl = Process.group_leader()

    try do
      Process.group_leader(self(), io)
      assert {:ok, "blue"} = UserInput.execute(%{"question" => "Pick a color"})
    after
      Process.group_leader(self(), original_gl)
    end
  end

  test "returns user response with options" do
    {:ok, io} = StringIO.open("2\n")
    original_gl = Process.group_leader()

    try do
      Process.group_leader(self(), io)

      assert {:ok, "2"} =
               UserInput.execute(%{
                 "question" => "Pick a color",
                 "options" => ["red", "blue", "green"]
               })
    after
      Process.group_leader(self(), original_gl)
    end
  end

  test "returns error on empty input" do
    {:ok, io} = StringIO.open("\n")
    original_gl = Process.group_leader()

    try do
      Process.group_leader(self(), io)
      assert {:error, msg} = UserInput.execute(%{"question" => "Pick a color"})
      assert msg =~ "No answer provided"
    after
      Process.group_leader(self(), original_gl)
    end
  end

  test "returns error on EOF" do
    {:ok, io} = StringIO.open("")
    original_gl = Process.group_leader()

    try do
      Process.group_leader(self(), io)
      assert {:error, msg} = UserInput.execute(%{"question" => "Pick a color"})
      assert msg =~ "EOF"
    after
      Process.group_leader(self(), original_gl)
    end
  end

  test "missing question returns error" do
    assert {:error, msg} = UserInput.execute(%{})
    assert msg =~ "Missing required parameter: question"
  end
end
