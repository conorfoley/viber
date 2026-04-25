defmodule Viber.Runtime.Conversation.RequestTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.Conversation.Request
  alias Viber.Runtime.BrowserContext

  describe "new/1" do
    test "builds from keyword list" do
      req = Request.new(session: self(), model: "sonnet", user_input: "hello")
      assert %Request{session: _, model: "sonnet", user_input: "hello"} = req
    end

    test "builds from map with atom keys" do
      req = Request.new(%{session: self(), model: "sonnet", user_input: "hello"})
      assert %Request{model: "sonnet"} = req
    end

    test "builds from map with string keys" do
      req = Request.new(%{"session" => self(), "model" => "sonnet", "user_input" => "hello"})
      assert %Request{model: "sonnet"} = req
    end

    test "passes through existing struct, coercing browser_context" do
      req = %Request{session: self(), model: "sonnet", user_input: "hi", browser_context: %{}}
      result = Request.new(req)
      assert result.browser_context == nil
    end

    test "raises on missing session" do
      assert_raise ArgumentError, ~r/missing required field :session/, fn ->
        Request.new(model: "sonnet", user_input: "hi")
      end
    end

    test "raises on missing model" do
      assert_raise ArgumentError, ~r/missing required field :model/, fn ->
        Request.new(session: self(), user_input: "hi")
      end
    end

    test "raises on missing user_input" do
      assert_raise ArgumentError, ~r/missing required field :user_input/, fn ->
        Request.new(session: self(), model: "sonnet")
      end
    end

    test "defaults permission_mode to :prompt" do
      req = Request.new(session: self(), model: "sonnet", user_input: "hi")
      assert req.permission_mode == :prompt
    end

    test "defaults project_root to cwd" do
      req = Request.new(session: self(), model: "sonnet", user_input: "hi")
      assert is_binary(req.project_root)
      assert req.project_root != "."
    end

    test "coerces browser_context map into struct" do
      req =
        Request.new(
          session: self(),
          model: "sonnet",
          user_input: "hi",
          browser_context: %{"url" => "https://example.com"}
        )

      assert %BrowserContext{url: "https://example.com"} = req.browser_context
    end

    test "nil browser_context stays nil" do
      req = Request.new(session: self(), model: "sonnet", user_input: "hi", browser_context: nil)
      assert req.browser_context == nil
    end

    test "event_handler defaults to noop" do
      req = Request.new(session: self(), model: "sonnet", user_input: "hi")
      assert req.event_handler.(:anything) == :ok
    end
  end
end
