defmodule Viber.Tools.ResultTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.{Failure, Result}

  describe "from_handler/1" do
    test "ok string" do
      assert %Result{outcome: :ok, output: "hi"} = Result.from_handler({:ok, "hi"})
    end

    test "ok non-string is inspected" do
      assert %Result{outcome: :ok, output: "%{a: 1}"} = Result.from_handler({:ok, %{a: 1}})
    end

    test "failure keeps outcome and reason" do
      failure = Failure.new(:unknown, "timed out", {:timeout, 5})

      assert %Result{outcome: :unknown, output: "timed out", reason: {:timeout, 5}} =
               Result.from_handler({:error, failure})
    end

    test "plain error term is :error with rendered message" do
      assert %Result{outcome: :error, output: "boom", reason: "boom"} =
               Result.from_handler({:error, "boom"})

      assert %Result{outcome: :error, output: "timed out", reason: :timeout} =
               Result.from_handler({:error, :timeout})
    end

    test "invalid return is :error" do
      assert %Result{outcome: :error, reason: :nope} = Result.from_handler(:nope)
    end
  end

  describe "model_output/1" do
    test "ok and error are unchanged" do
      assert Result.model_output(Result.ok("x")) == "x"
      assert Result.model_output(Result.failure(:error, "bad")) == "bad"
    end

    test "unknown, refused and not_sent are prefixed" do
      assert Result.model_output(Result.failure(:unknown, "m")) =~
               ~r/^\[outcome: unknown .*check state before retrying\]\nm$/

      assert Result.model_output(Result.failure(:refused, "m")) =~ ~r/^\[outcome: refused/
      assert Result.model_output(Result.failure(:not_sent, "m")) =~ ~r/^\[outcome: not_sent/
    end
  end

  test "error?/1" do
    refute Result.error?(Result.ok("x"))
    assert Result.error?(Result.failure(:refused, "x"))
  end

  test "outcome_from_string/1 only accepts known outcomes" do
    assert Result.outcome_from_string("unknown") == :unknown
    assert Result.outcome_from_string(:ok) == :ok
    assert Result.outcome_from_string("bogus") == nil
    assert Result.outcome_from_string(nil) == nil
  end
end
