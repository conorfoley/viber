defmodule Viber.Runtime.BrowserContextTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.BrowserContext

  describe "new/1" do
    test "nil returns nil" do
      assert BrowserContext.new(nil) == nil
    end

    test "empty map returns nil" do
      assert BrowserContext.new(%{}) == nil
    end

    test "struct with all nils returns nil" do
      assert BrowserContext.new(%BrowserContext{}) == nil
    end

    test "populated struct passes through" do
      ctx = %BrowserContext{url: "https://example.com"}
      assert BrowserContext.new(ctx) == ctx
    end

    test "coerces atom-keyed map" do
      ctx = BrowserContext.new(%{url: "https://example.com", title: "Example"})
      assert %BrowserContext{url: "https://example.com", title: "Example"} = ctx
    end

    test "coerces string-keyed map" do
      ctx = BrowserContext.new(%{"url" => "https://example.com", "selection" => "hello"})
      assert %BrowserContext{url: "https://example.com", selection: "hello"} = ctx
    end

    test "ignores unknown keys" do
      ctx = BrowserContext.new(%{"url" => "https://example.com", "unknown_field" => "ignored"})
      assert %BrowserContext{url: "https://example.com"} = ctx
    end

    test "ignores values with wrong types" do
      assert BrowserContext.new(%{"url" => 123}) == nil
      assert BrowserContext.new(%{"viewport" => "not a map"}) == nil
    end

    test "coerces map keys for viewport and focused_element" do
      ctx =
        BrowserContext.new(%{
          "viewport" => %{"width" => 1280, "height" => 800},
          "focused_element" => %{"tag" => "input"}
        })

      assert %BrowserContext{
               viewport: %{"width" => 1280, "height" => 800},
               focused_element: %{"tag" => "input"}
             } = ctx
    end
  end

  describe "empty?/1" do
    test "all nil fields is empty" do
      assert BrowserContext.empty?(%BrowserContext{})
    end

    test "any populated field is not empty" do
      refute BrowserContext.empty?(%BrowserContext{url: "https://example.com"})
    end
  end
end
