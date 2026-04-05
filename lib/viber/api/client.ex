defmodule Viber.API.Client do
  @moduledoc """
  Unified LLM client with model alias resolution, provider detection, and retry.
  """

  require Logger

  alias Viber.API.{Error, MessageRequest, MessageResponse}
  alias Viber.API.Providers.{Anthropic, OpenAICompat}

  @type provider_kind :: :anthropic | :openai | :xai

  @model_aliases %{
    "opus" => "claude-opus-4-6",
    "sonnet" => "claude-sonnet-4-6",
    "haiku" => "claude-haiku-4-5-20251213",
    "grok" => "grok-3",
    "grok-mini" => "grok-3-mini"
  }

  @spec resolve_model_alias(String.t()) :: String.t()
  def resolve_model_alias(model) do
    model = String.trim(model)
    Map.get(@model_aliases, String.downcase(model), model)
  end

  @spec detect_provider(String.t()) :: provider_kind()
  def detect_provider(model) do
    model = resolve_model_alias(model)

    cond do
      String.starts_with?(model, "claude") -> :anthropic
      String.starts_with?(model, "grok") -> :xai
      String.starts_with?(model, "gpt-") -> :openai
      String.starts_with?(model, "o1-") -> :openai
      String.starts_with?(model, "o3-") -> :openai
      String.starts_with?(model, "o4-") -> :openai
      System.get_env("ANTHROPIC_API_KEY") -> :anthropic
      System.get_env("OPENAI_API_KEY") -> :openai
      System.get_env("XAI_API_KEY") -> :xai
      true -> :anthropic
    end
  end

  @spec max_tokens_for_model(String.t()) :: pos_integer()
  def max_tokens_for_model(model) do
    canonical = resolve_model_alias(model)

    if String.contains?(canonical, "opus") do
      32_000
    else
      64_000
    end
  end

  @spec from_model(String.t()) :: {:ok, provider_kind(), module()} | {:error, Error.t()}
  def from_model(model) do
    case detect_provider(model) do
      :anthropic -> {:ok, :anthropic, Anthropic}
      :openai -> {:ok, :openai, OpenAICompat}
      :xai -> {:ok, :xai, OpenAICompat}
    end
  end

  @spec send_message(String.t(), MessageRequest.t()) ::
          {:ok, MessageResponse.t()} | {:error, Error.t()}
  def send_message(model, %MessageRequest{} = request) do
    model = resolve_model_alias(model)
    request = %{request | model: model}

    {:ok, _kind, module} = from_model(model)
    send_with_retry(module, request)
  end

  @spec stream_message(String.t(), MessageRequest.t()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def stream_message(model, %MessageRequest{} = request) do
    model = resolve_model_alias(model)
    request = %{request | model: model}

    {:ok, kind, module} = from_model(model)
    Logger.info("Streaming message: model=#{model} provider=#{kind} module=#{module}")
    module.stream_message(request)
  end

  @spec send_with_retry(module(), MessageRequest.t(), keyword()) ::
          {:ok, MessageResponse.t()} | {:error, Error.t()}
  def send_with_retry(module, request, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    do_send_with_retry(module, request, 0, max_attempts)
  end

  defp do_send_with_retry(module, request, attempt, max_attempts) do
    case module.send_message(request) do
      {:ok, _} = success ->
        success

      {:error, %Error{} = err} ->
        if Error.retryable?(err) and attempt < max_attempts - 1 do
          Process.sleep(backoff(attempt))
          do_send_with_retry(module, request, attempt + 1, max_attempts)
        else
          {:error, err}
        end
    end
  end

  defp backoff(attempt) do
    trunc(:math.pow(2, attempt) * 1_000)
  end
end
