defmodule Viber.Commands.Handlers.EffortTest do
  use ExUnit.Case, async: true

  alias Viber.Commands.Handlers.Effort
  alias Viber.Commands.Result
  alias Viber.Runtime.Config

  test "no args shows current effort and available levels" do
    assert {:ok, text} = Effort.execute([], %{config: %Config{effort: "low"}})
    assert text =~ "Current effort: low"
    assert text =~ "low, medium, high, xhigh, max"
  end

  test "no args with unset effort shows default" do
    assert {:ok, text} = Effort.execute([], %{config: nil})
    assert text =~ "default (high)"
  end

  test "setting a valid level patches config via run/3" do
    assert {:ok, %Result{} = result} = Effort.run(nil, ["low"], %{})
    assert result.text =~ "Effort set to low"
    assert result.state_patch == %{config_patch: %{effort: "low"}}
  end

  test "reset clears the effort" do
    assert {:ok, %Result{} = result} = Effort.run(nil, ["reset"], %{})
    assert result.state_patch == %{config_patch: %{effort: nil}}
  end

  test "invalid level errors with the level list" do
    assert {:error, message} = Effort.execute(["turbo"], %{})
    assert message =~ "Unknown effort level 'turbo'"
    assert message =~ "low, medium, high, xhigh, max"
  end
end
