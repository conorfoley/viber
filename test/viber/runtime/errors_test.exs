defmodule Viber.Runtime.ErrorsTest do
  use ExUnit.Case, async: true

  alias Viber.API.Error, as: APIError
  alias Viber.Runtime.Errors

  describe "from_caught/3" do
    test "normalizes raised errors to exception structs" do
      assert %ArgumentError{} = Errors.from_caught(:error, :badarg, [])

      assert %RuntimeError{message: "boom"} =
               Errors.from_caught(:error, %RuntimeError{message: "boom"})
    end

    test "tags throws and exits" do
      assert Errors.from_caught(:throw, :x) == {:throw, :x}
      assert Errors.from_caught(:exit, :killed) == {:exit, :killed}
    end
  end

  describe "classification" do
    test "retryable? follows the API error flag and unwraps stream errors" do
      err = APIError.api_error(529, "overloaded", true)
      assert Errors.retryable?(err)
      assert Errors.retryable?({:stream_error, err})
      refute Errors.retryable?(:timeout)
    end

    test "context_window_exceeded? detects overflow messages" do
      err = APIError.api_error(400, "prompt is too long: 250000 tokens", false)
      assert Errors.context_window_exceeded?(err)
      assert Errors.context_window_exceeded?(APIError.retries_exhausted(3, err))
      refute Errors.context_window_exceeded?(APIError.api_error(400, "bad request", false))
    end
  end

  describe "message/1" do
    test "renders common reasons" do
      assert Errors.message("plain") == "plain"
      assert Errors.message(%RuntimeError{message: "boom"}) == "boom"
      assert Errors.message(APIError.api_error(500, "server", true)) == "server"
      assert Errors.message(:max_iterations) == "maximum iterations exceeded"
      assert Errors.message({:throw, :x}) == "thrown: :x"
      assert Errors.message({:weird, 1}) == "{:weird, 1}"
    end
  end

  describe "to_wire/1" do
    test "produces JSON-encodable maps" do
      err = APIError.api_error(429, "rate limited", true)
      wire = Errors.to_wire({:stream_error, err})

      assert wire.kind == "api_error"
      assert wire.status == 429
      assert wire.retryable
      assert wire.stream
      assert {:ok, _} = Jason.encode(wire)

      assert Errors.to_wire(:max_iterations) == %{kind: "max_iterations"}
      assert Errors.to_wire({:exit, :killed}) == %{kind: "exit"}
      assert Errors.to_wire({1, 2, 3}) == %{kind: "other"}
    end
  end
end
