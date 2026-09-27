defmodule Viber.Commands.Handlers.Model do
  @moduledoc """
  Handler for the /model command.
  """

  use Viber.Commands.Handler

  alias Viber.API.{Client, Providers.Ollama}

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute([], context) do
    model = context[:model] || "unknown"
    resolved = Client.resolve_model_alias(model)

    current_model =
      if model == resolved do
        "Current model: #{model}"
      else
        "Current model: #{model} (#{resolved})"
      end

    {:ok, Enum.join([current_model | ollama_model_lines(context, model)], "\n")}
  end

  def execute(["list" | _], _context) do
    aliases = Client.model_aliases()

    groups =
      aliases
      |> Enum.group_by(fn {_alias, full} -> provider_label(full) end)
      |> Enum.sort_by(fn {provider, _} -> provider end)

    lines =
      Enum.flat_map(groups, fn {provider, entries} ->
        rows =
          entries
          |> Enum.sort_by(fn {alias_, _} -> alias_ end)
          |> Enum.map(fn {alias_, full} -> "    #{alias_} → #{full}" end)

        ["  #{provider}:" | rows]
      end)

    header = "Available model aliases:"
    {:ok, Enum.join([header | lines], "\n")}
  end

  def execute([new_model | _], _context) do
    resolved = Client.resolve_model_alias(new_model)

    if new_model == resolved do
      {:ok, "Switched to model: #{new_model}"}
    else
      {:ok, "Switched to model: #{new_model} (#{resolved})"}
    end
  end

  @doc """
  Builds the choices for the interactive `/model` picker.

  Installed Ollama models are listed first, followed by the hosted models from the
  alias table. Returns the `{label, model}` choices and the Ollama lookup result.
  """
  @spec picker_choices(map(), keyword()) ::
          {[{String.t(), String.t()}], {:ok, [String.t()]} | {:error, term()}}
  def picker_choices(context, opts \\ []) do
    model = context[:model] || ""
    current = Client.resolve_model_alias(model)
    base_url = configured_ollama_base_url(context, model)
    ollama_result = Ollama.list_models(Keyword.put(opts, :base_url, base_url))

    ollama_choices =
      case ollama_result do
        {:ok, models} -> Enum.map(models, &{"ollama:#{&1}", "Ollama"})
        {:error, _reason} -> []
      end

    hosted_choices =
      Client.model_aliases()
      |> Enum.reject(fn {_alias, full} -> String.starts_with?(full, "ollama:") end)
      |> Enum.group_by(fn {_alias, full} -> full end, fn {alias_, _full} -> alias_ end)
      |> Enum.map(fn {full, aliases} -> {full, provider_label(full), Enum.sort(aliases)} end)
      |> Enum.sort_by(fn {full, provider, _aliases} -> {provider, full} end)
      |> Enum.map(fn {full, provider, aliases} -> {full, provider, aliases -- [full]} end)

    choices =
      Enum.map(ollama_choices, fn {full, provider} -> {full, provider, []} end) ++ hosted_choices

    labelled =
      Enum.map(choices, fn {full, provider, aliases} ->
        {choice_label(full, provider, aliases, full == current), full}
      end)

    {labelled, ollama_result}
  end

  defp choice_label(full, provider, aliases, current?) do
    alias_part = if aliases == [], do: "", else: " (#{Enum.join(aliases, ", ")})"
    current_part = if current?, do: "  ← current", else: ""
    "#{String.pad_trailing(provider, 10)} #{full}#{alias_part}#{current_part}"
  end

  defp ollama_model_lines(context, model) do
    base_url = configured_ollama_base_url(context, model)

    case Ollama.list_models(base_url: base_url) do
      {:ok, []} ->
        ["Ollama models: none installed"]

      {:ok, models} ->
        ["Ollama models (select with /model):", Enum.map_join(models, "\n", &"  ollama:#{&1}")]

      {:error, _reason} ->
        ["Ollama models: unavailable (could not connect to Ollama)"]
    end
  end

  defp configured_ollama_base_url(%{config: %{provider: "ollama", base_url: base_url}}, _model),
    do: base_url

  defp configured_ollama_base_url(%{config: %{base_url: base_url}}, model) do
    if Client.detect_provider(model) == :ollama, do: base_url
  end

  defp configured_ollama_base_url(_context, _model), do: nil

  defp provider_label("claude" <> _), do: "Anthropic"
  defp provider_label("grok" <> _), do: "xAI"
  defp provider_label("gpt-" <> _), do: "OpenAI"
  defp provider_label("ollama:" <> _), do: "Ollama"

  defp provider_label("o" <> rest) do
    case rest do
      <<c, _::binary>> when c in ?0..?9 -> "OpenAI"
      _ -> "Other"
    end
  end

  defp provider_label(_), do: "Other"
end
