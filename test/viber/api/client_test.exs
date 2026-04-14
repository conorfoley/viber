defmodule Viber.API.ClientTest do
  use ExUnit.Case, async: false

  alias Viber.API.{Client, Error, InputMessage, MessageRequest, MessageResponse, Usage}

  test "resolves model aliases" do
    assert Client.resolve_model_alias("opus") == "claude-opus-4-6"
    assert Client.resolve_model_alias("sonnet") == "claude-sonnet-4-6"
    assert Client.resolve_model_alias("haiku") == "claude-haiku-4-5-20251213"
    assert Client.resolve_model_alias("grok") == "grok-3"
    assert Client.resolve_model_alias("grok-mini") == "grok-3-mini"
    assert Client.resolve_model_alias("claude-sonnet-4-6") == "claude-sonnet-4-6"
  end

  test "resolves ollama model aliases" do
    assert Client.resolve_model_alias("llama3") == "ollama:llama3"
    assert Client.resolve_model_alias("mistral") == "ollama:mistral"
    assert Client.resolve_model_alias("codestral") == "ollama:codestral"
    assert Client.resolve_model_alias("phi4") == "ollama:phi4"
    assert Client.resolve_model_alias("gemma3") == "ollama:gemma3"
    assert Client.resolve_model_alias("deepseek-r1") == "ollama:deepseek-r1"
  end

  test "bare ollama model id passthrough" do
    assert Client.resolve_model_alias("ollama:llama3") == "ollama:llama3"
    assert Client.resolve_model_alias("ollama:mistral:latest") == "ollama:mistral:latest"
  end

  test "detects provider from model names" do
    assert Client.detect_provider("claude-sonnet-4-6") == :anthropic
    assert Client.detect_provider("opus") == :anthropic
    assert Client.detect_provider("grok-3") == :xai
    assert Client.detect_provider("grok") == :xai
    assert Client.detect_provider("gpt-4o") == :openai
    assert Client.detect_provider("o3-mini") == :openai
  end

  test "detects :ollama for ollama: prefixed models without env vars" do
    System.delete_env("OLLAMA_HOST")
    assert Client.detect_provider("ollama:llama3") == :ollama
    assert Client.detect_provider("ollama:mistral:latest") == :ollama
  end

  test "detects :ollama via alias resolution" do
    System.delete_env("OLLAMA_HOST")
    assert Client.detect_provider("llama3") == :ollama
    assert Client.detect_provider("mistral") == :ollama
  end

  test "detects :ollama via OLLAMA_HOST env var for bare model names" do
    prev_anthropic = System.get_env("ANTHROPIC_API_KEY")
    prev_openai = System.get_env("OPENAI_API_KEY")
    prev_xai = System.get_env("XAI_API_KEY")

    System.delete_env("ANTHROPIC_API_KEY")
    System.delete_env("OPENAI_API_KEY")
    System.delete_env("XAI_API_KEY")
    System.put_env("OLLAMA_HOST", "http://localhost:11434")

    on_exit(fn ->
      System.delete_env("OLLAMA_HOST")
      if prev_anthropic, do: System.put_env("ANTHROPIC_API_KEY", prev_anthropic)
      if prev_openai, do: System.put_env("OPENAI_API_KEY", prev_openai)
      if prev_xai, do: System.put_env("XAI_API_KEY", prev_xai)
    end)

    assert Client.detect_provider("custom-local-model") == :ollama
  end

  test "max_tokens_for_model returns nil for ollama models" do
    assert Client.max_tokens_for_model("ollama:llama3") == nil
    assert Client.max_tokens_for_model("llama3") == nil
    assert Client.max_tokens_for_model("mistral") == nil
  end

  test "max_tokens_for_model returns 32k for opus, 64k otherwise" do
    assert Client.max_tokens_for_model("opus") == 32_000
    assert Client.max_tokens_for_model("sonnet") == 64_000
    assert Client.max_tokens_for_model("grok-3") == 64_000
  end

  test "from_model returns provider kind and module" do
    assert {:ok, :anthropic, Viber.API.Providers.Anthropic} =
             Client.from_model("claude-sonnet-4-6")

    assert {:ok, :xai, Viber.API.Providers.OpenAICompat} = Client.from_model("grok-3")
    assert {:ok, :openai, Viber.API.Providers.OpenAICompat} = Client.from_model("gpt-4o")
  end

  test "from_model returns :ollama for ollama: prefix" do
    System.delete_env("OLLAMA_HOST")
    assert {:ok, :ollama, Viber.API.Providers.OpenAICompat} = Client.from_model("ollama:llama3")
    assert {:ok, :ollama, Viber.API.Providers.OpenAICompat} = Client.from_model("llama3")
  end

  describe "send_with_retry" do
    setup do
      request = %MessageRequest{
        model: "test-model",
        max_tokens: 1024,
        messages: [InputMessage.user_text("hi")]
      }

      response = %MessageResponse{
        id: "msg_1",
        type: "message",
        role: "assistant",
        content: [%{type: "text", text: "hello"}],
        model: "test-model",
        usage: %Usage{input_tokens: 10, output_tokens: 5}
      }

      %{request: request, response: response}
    end

    test "returns success on first try", %{request: request, response: response} do
      {:ok, _} = Viber.MockProvider.start([{:ok, response}])

      assert {:ok, ^response} = Client.send_with_retry(Viber.MockProvider, request)

      Viber.MockProvider.stop()
    end

    test "retries on retryable errors", %{request: request, response: response} do
      retryable_error = {:error, %Error{type: :api, message: "503", retryable: true}}

      {:ok, _} = Viber.MockProvider.start([retryable_error, {:ok, response}])

      assert {:ok, ^response} =
               Client.send_with_retry(Viber.MockProvider, request, max_attempts: 3)

      Viber.MockProvider.stop()
    end

    test "does not retry non-retryable errors", %{request: request} do
      non_retryable = {:error, %Error{type: :auth, message: "unauthorized", retryable: false}}

      {:ok, _} = Viber.MockProvider.start([non_retryable])

      assert {:error, %Error{type: :auth}} =
               Client.send_with_retry(Viber.MockProvider, request, max_attempts: 3)

      Viber.MockProvider.stop()
    end
  end
end
