defmodule Viber.Commands.Handlers.ThinkingTest do
  use ExUnit.Case, async: true

  alias Viber.Commands.Handlers.Thinking
  alias Viber.Commands.Result
  alias Viber.Runtime.Config

  test "no args shows current mode and billing note" do
    assert {:ok, text} = Thinking.execute([], %{config: %Config{thinking: "off"}})
    assert text =~ "Current thinking mode: off"
    assert text =~ "billed the same"
  end

  test "no args with unset mode shows adaptive default" do
    assert {:ok, text} = Thinking.execute([], %{config: nil})
    assert text =~ "adaptive (default)"
  end

  test "off patches config and warns about reliability" do
    assert {:ok, %Result{} = result} = Thinking.run(nil, ["off"], %{})
    assert result.state_patch == %{config_patch: %{thinking: "off"}}
    assert result.text =~ "Fable 5 cannot disable thinking"
  end

  test "adaptive patches config" do
    assert {:ok, %Result{} = result} = Thinking.run(nil, ["adaptive"], %{})
    assert result.state_patch == %{config_patch: %{thinking: "adaptive"}}
  end

  test "reset clears the mode" do
    assert {:ok, %Result{} = result} = Thinking.run(nil, ["reset"], %{})
    assert result.state_patch == %{config_patch: %{thinking: nil}}
  end

  test "invalid mode errors" do
    assert {:error, message} = Thinking.execute(["sometimes"], %{})
    assert message =~ "Unknown thinking mode 'sometimes'"
  end
end
