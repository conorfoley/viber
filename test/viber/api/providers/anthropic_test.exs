defmodule Viber.API.Providers.AnthropicTest do
  use ExUnit.Case, async: true

  alias Viber.API.{Error, InputMessage, MessageRequest}
  alias Viber.API.Providers.Anthropic

  test "returns missing credentials when no API key set" do
    original = System.get_env("ANTHROPIC_API_KEY")

    try do
      System.delete_env("ANTHROPIC_API_KEY")

      request = %MessageRequest{
        model: "claude-sonnet-4-6",
        max_tokens: 1024,
        messages: [InputMessage.user_text("hello")]
      }

      assert {:error, %Error{type: :missing_credentials}} = Anthropic.send_message(request)
    after
      if original, do: System.put_env("ANTHROPIC_API_KEY", original)
    end
  end

  describe "apply_cache_control/1" do
    test "wraps system in a cached content block and marks the last message block" do
      request = %MessageRequest{
        model: "claude-opus-5",
        max_tokens: 1024,
        system: "system prompt",
        messages: [
          InputMessage.user_text("first"),
          InputMessage.user_text("last")
        ]
      }

      cached = Anthropic.apply_cache_control(request)

      assert cached.system == [
               %{type: "text", text: "system prompt", cache_control: %{type: "ephemeral"}}
             ]

      [first, last] = cached.messages
      assert first.content == [%{type: "text", text: "first"}]

      assert last.content == [
               %{type: "text", text: "last", cache_control: %{type: "ephemeral"}}
             ]
    end

    test "marks tool_result blocks but not thinking blocks" do
      tool_result_msg = InputMessage.user_tool_result("tu_1", "output", false)

      request = %MessageRequest{
        model: "claude-opus-5",
        max_tokens: 1024,
        messages: [tool_result_msg]
      }

      [msg] = Anthropic.apply_cache_control(request).messages
      [block] = msg.content
      assert block.cache_control == %{type: "ephemeral"}

      thinking_msg = %InputMessage{
        role: "assistant",
        content: [%{type: "thinking", thinking: "hmm", signature: "sig"}]
      }

      request = %{request | messages: [thinking_msg]}
      [msg] = Anthropic.apply_cache_control(request).messages
      [block] = msg.content
      refute Map.has_key?(block, :cache_control)
    end

    test "leaves empty system and empty messages untouched" do
      request = %MessageRequest{model: "claude-opus-5", max_tokens: 1024, messages: []}
      cached = Anthropic.apply_cache_control(request)

      assert cached.system == nil
      assert cached.messages == []
    end
  end
end
