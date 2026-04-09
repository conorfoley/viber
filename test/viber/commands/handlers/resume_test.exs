defmodule Viber.Commands.Handlers.ResumeTest do
  use ExUnit.Case, async: true

  alias Viber.Commands.Handlers.Resume
  alias Viber.Runtime.SessionStore

  describe "execute/2 with no args" do
    test "returns no sessions message when repo unavailable or empty" do
      {:ok, output} = Resume.execute([], %{})

      if SessionStore.available?() do
        assert output =~ "sessions" or output =~ "No previous sessions"
      else
        assert output == "No previous sessions found."
      end
    end
  end

  describe "execute/2 with invalid selector" do
    test "returns error for nonexistent session id" do
      result = Resume.execute(["nonexistent-id-12345"], %{})

      case result do
        {:error, msg} ->
          assert msg =~ "not found" or msg =~ "Failed"

        {:resume, _pid} ->
          flunk("Should not resume a nonexistent session")
      end
    end
  end
end
