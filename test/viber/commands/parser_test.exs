defmodule Viber.Commands.ParserTest do
  use ExUnit.Case, async: true

  alias Viber.Commands.Parser

  test "parses /help to command tuple" do
    assert {:command, "help", []} = Parser.parse("/help")
  end

  test "parses /model with argument" do
    assert {:command, "model", ["sonnet"]} = Parser.parse("/model sonnet")
  end

  test "fuzzy matches /hlep to suggestion for help" do
    assert {:suggestion, "hlep", suggestions} = Parser.parse("/hlep")
    assert "help" in suggestions
  end

  test "non-slash input returns not_command" do
    assert {:not_command, "hello"} = Parser.parse("hello")
  end

  test "command? detects slash prefix" do
    assert Parser.command?("/help")
    refute Parser.command?("hello")
  end

  test "parses command with multiple args" do
    assert {:command, "config", ["model", "value"]} = Parser.parse("/config model value")
  end
end
