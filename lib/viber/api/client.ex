defmodule Viber.API.Client do
  @moduledoc """
  Unified LLM client with model alias resolution, provider detection, and retry.
  """

  require Logger

  alias Viber.API.{Error, MessageRequest, MessageResponse}
  alias Viber.API.Providers.{Anthropic, OpenAICompat}

  @type provider_kind :: :anthropic | :openai | :xai | :ollama

  @model_aliases %{
    "fable" => "claude-fable-5",
    "opus" => "claude-opus-5",
    "sonnet" => "claude-sonnet-5",
    "haiku" => "claude-haiku-4-5",
    "grok" => "grok-3",
    "grok-mini" => "grok-3-mini",
    "gpt4o" => "gpt-4o",
    "gpt41" => "gpt-4.1",
    "o3" => "o3",
    "o3-mini" => "o3-mini",
    "o4-mini" => "o4-mini",
    "llama3" => "ollama:llama3",
    "llama3.1" => "ollama:llama3.1",
    "llama3.2" => "ollama:llama3.2",
    "mistral" => "ollama:mistral",
    "codestral" => "ollama:codestral",
    "qwen2.5" => "ollama:qwen2.5",
    "phi4" => "ollama:phi4",
    "gemma3" => "ollama:gemma3",
    "deepseek-r1" => "ollama:deepseek-r1"
  }

  @spec model_aliases() :: %{String.t() => String.t()}
  def model_aliases, do: @model_aliases

  @spec resolve_model_alias(String.t()) :: String.t()
  def resolve_model_alias(model) do
    model = String.trim(model)
    Map.get(@model_aliases, String.downcase(model), model)
  end

  @spec detect_provider(String.t()) :: provider_kind()
  def detect_provider(model) do
    model = resolve_model_alias(model)

    cond do
      String.starts_with?(model, "ollama:") ->
        :ollama

      String.starts_with?(model, "claude") ->
        :anthropic

      String.starts_with?(model, "grok") ->
        :xai

      String.starts_with?(model, "gpt-") ->
        :openai

      String.match?(model, ~r/^o\d/) ->
        :openai

      env_key_set?("ANTHROPIC_API_KEY") ->
        :anthropic

      env_key_set?("OPENAI_API_KEY") ->
        :openai

      env_key_set?("XAI_API_KEY") ->
        :xai

      env_key_set?("OLLAMA_HOST") ->
        :ollama

      true ->
        Logger.warning("No API key found in environment, defaulting to :anthropic")
        :anthropic
    end
  end

  @model_max_tokens %{
    "claude-fable-5" => 64_000,
    "claude-opus-5" => 64_000,
    "claude-sonnet-5" => 64_000,
    "claude-haiku-4-5" => 64_000,
    "claude-opus-4-6" => 32_000,
    "claude-sonnet-4-6" => 64_000,
    "claude-haiku-4-5-20251213" => 64_000,
    "gpt-4o" => 16_384,
    "gpt-4.1" => 32_768,
    "o3" => 100_000,
    "o3-mini" => 65_536,
    "o4-mini" => 100_000,
    "grok-3" => 131_072,
    "grok-3-mini" => 131_072
  }

  @spec max_tokens_for_model(String.t()) :: pos_integer() | nil
  def max_tokens_for_model(model) do
    canonical = resolve_model_alias(model)

    cond do
      String.starts_with?(canonical, "ollama:") ->
        nil

      true ->
        Map.get(@model_max_tokens, canonical, 64_000)
    end
  end

  @adaptive_thinking_summarized ~w[
    claude-fable-5
    claude-mythos
    claude-opus-5
    claude-opus-4-8
    claude-opus-4-7
    claude-sonnet-5
  ]

  @adaptive_thinking_basic ~w[claude-opus-4-6 claude-sonnet-4-6]

  @effort_levels ~w[low medium high xhigh max]

  @doc """
  Returns the effort levels accepted by `output_config/2`.
  """
  @spec effort_levels() :: [String.t()]
  def effort_levels, do: @effort_levels

  @thinking_modes ~w[adaptive off]

  @doc """
  Returns the thinking modes accepted by `thinking_config/3`.
  """
  @spec thinking_modes() :: [String.t()]
  def thinking_modes, do: @thinking_modes

  @doc """
  Returns the `thinking` request parameter for a model, or `nil` when the
  parameter should be omitted.

  With mode `"adaptive"` (the default), adaptive thinking is enabled on
  models that support it. Models with an omitted-by-default thinking display
  get `display: "summarized"` so reasoning can be streamed to the user.
  Note that `display` controls visibility only — thinking is billed the same
  whatever the display setting.

  With mode `"off"`, thinking is disabled where the API allows it:

    * Opus 5 / Sonnet 5 — sent as `{type: "disabled"}`. Opus 5 rejects
      `disabled` at effort `xhigh`/`max`, so adaptive is kept there.
    * Opus 4.8 / 4.7 / 4.6, Sonnet 4.6 — the parameter is omitted, which
      runs those models without thinking.
    * Fable 5 / Mythos 5 — thinking is always on and cannot be disabled;
      the parameter is omitted (which runs adaptive).

  Prefer lowering `effort` over turning thinking off: disabled thinking can
  degrade tool-call reliability on current models.
  """
  @spec thinking_config(String.t(), String.t(), String.t() | nil) :: map() | nil
  def thinking_config(model, mode \\ "adaptive", effort \\ nil)

  def thinking_config(model, "off", effort) do
    canonical = resolve_model_alias(model)

    cond do
      String.starts_with?(canonical, "claude-opus-5") and effort in ["xhigh", "max"] ->
        %{type: "adaptive", display: "summarized"}

      prefix_match?(canonical, ["claude-opus-5", "claude-sonnet-5"]) ->
        %{type: "disabled"}

      true ->
        nil
    end
  end

  def thinking_config(model, _mode, _effort) do
    canonical = resolve_model_alias(model)

    cond do
      prefix_match?(canonical, @adaptive_thinking_summarized) ->
        %{type: "adaptive", display: "summarized"}

      prefix_match?(canonical, @adaptive_thinking_basic) ->
        %{type: "adaptive"}

      true ->
        nil
    end
  end

  @doc """
  Returns the `output_config` request parameter carrying the effort level,
  or `nil` when no effort is requested or the model does not support it.
  """
  @spec output_config(String.t(), String.t() | nil) :: map() | nil
  def output_config(_model, nil), do: nil

  def output_config(model, effort) when is_binary(effort) do
    canonical = resolve_model_alias(model)

    cond do
      effort not in @effort_levels ->
        nil

      prefix_match?(canonical, @adaptive_thinking_summarized) ->
        %{effort: effort}

      prefix_match?(canonical, @adaptive_thinking_basic) ->
        %{effort: if(effort == "xhigh", do: "high", else: effort)}

      true ->
        nil
    end
  end

  defp prefix_match?(model, prefixes) do
    Enum.any?(prefixes, &String.starts_with?(model, &1))
  end

  @spec from_model(String.t()) :: {:ok, provider_kind(), module()}
  def from_model(model) do
    case detect_provider(model) do
      :anthropic -> {:ok, :anthropic, Anthropic}
      :openai -> {:ok, :openai, OpenAICompat}
      :xai -> {:ok, :xai, OpenAICompat}
      :ollama -> {:ok, :ollama, OpenAICompat}
    end
  end

  @spec send_message(String.t(), MessageRequest.t(), keyword()) ::
          {:ok, MessageResponse.t()} | {:error, Error.t()}
  def send_message(model, %MessageRequest{} = request, opts \\ []) do
    model = resolve_model_alias(model)
    request = %{request | model: model}

    with {:ok, _kind, module} <- from_model(model) do
      request = apply_config_overrides(request, opts)
      send_with_retry(module, request)
    end
  end

  @spec stream_message(String.t(), MessageRequest.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def stream_message(model, %MessageRequest{} = request, opts \\ []) do
    model = resolve_model_alias(model)
    request = %{request | model: model}

    with {:ok, kind, module} <- from_model(model) do
      Logger.info("Streaming message: model=#{model} provider=#{kind} module=#{module}")
      request = apply_config_overrides(request, opts)
      module.stream_message(request)
    end
  end

  defp apply_config_overrides(request, opts) do
    overrides =
      Enum.reduce([:base_url, :api_key], %{}, fn key, acc ->
        case Keyword.get(opts, key) do
          nil -> acc
          val -> Map.put(acc, key, val)
        end
      end)

    if map_size(overrides) > 0 do
      %{request | provider_overrides: overrides}
    else
      request
    end
  end

  @spec send_with_retry(module(), MessageRequest.t(), keyword()) ::
          {:ok, MessageResponse.t()} | {:error, Error.t()}
  def send_with_retry(module, request, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    timeout = Keyword.get(opts, :timeout, 60_000)

    task =
      Task.Supervisor.async_nolink(Viber.TaskSupervisor, fn ->
        do_send_with_retry(module, request, 0, max_attempts)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, %Error{type: :http, message: "retry timed out", retryable: false}}
    end
  end

  defp do_send_with_retry(module, request, attempt, max_attempts) do
    case module.send_message(request) do
      {:ok, _} = success ->
        success

      {:error, %Error{} = err} ->
        if Error.retryable?(err) and attempt < max_attempts - 1 do
          Logger.debug(
            "Retrying request (attempt #{attempt + 1}/#{max_attempts}) after #{backoff(attempt)}ms"
          )

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

  defp env_key_set?(var), do: Viber.Env.key_set?(var)
end
