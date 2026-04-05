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
end
