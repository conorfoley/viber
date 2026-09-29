defmodule Viber.Runtime.Compact do
  @moduledoc """
  Conversation history compaction via LLM summarization.

  The summary is a typed model call (`Viber.Runtime.Predict`) against
  `summary_signature/0`, so it always carries the same sections: summary,
  files, decisions, open tasks and errors. If the call fails, the old
  messages are kept as plain text instead.
  """

  require Logger

  alias Viber.Runtime.{Predict, Session, Signature, Usage}

  @chars_per_token 4
  @default_token_threshold 100_000
  @preserve_recent 4

  @summary_spec "conversation -> summary, files: list[string], decisions: list[string], open_tasks: list[string], errors: list[string]"

  @summary_instructions """
  Summarize the conversation into a concise but thorough reference.
  summary: what happened, in a few short paragraphs; reference code by file path instead of quoting it.
  files: every file path mentioned.
  decisions: key decisions made and changes applied.
  open_tasks: unresolved tasks and next steps.
  errors: errors encountered and tool calls whose outcome was not ok.
  Omit greetings and tool output that is no longer relevant.
  """

  @spec should_compact?(GenServer.server(), keyword()) :: boolean()
  def should_compact?(session, opts \\ []) do
    threshold = Keyword.get(opts, :token_threshold, @default_token_threshold)
    messages = Session.get_messages(session)
    compactable = Enum.drop(messages, -@preserve_recent)

    compactable != [] and estimate_tokens(compactable) >= threshold
  end

  @spec estimate_tokens([map()]) :: non_neg_integer()
  def estimate_tokens(messages) do
    messages
    |> Enum.map(fn msg ->
      msg.blocks
      |> Enum.map(&block_chars/1)
      |> Enum.sum()
    end)
    |> Enum.sum()
    |> div(@chars_per_token)
  end

  @spec compact(GenServer.server(), keyword()) :: {:ok, non_neg_integer()}
  def compact(session, opts \\ []) do
    messages = Session.get_messages(session)
    preserve = Keyword.get(opts, :preserve_recent, @preserve_recent)
    model = Keyword.get(opts, :model, "ollama:qwen3.8:latest")
    predict_opts = [model: model, provider_module: Keyword.get(opts, :provider_module)]

    if length(messages) <= preserve do
      {:ok, 0}
    else
      do_compact(session, messages, preserve, predict_opts)
    end
  end

  defp do_compact(session, messages, preserve, predict_opts) do
    {old_messages, recent} = Enum.split(messages, length(messages) - preserve)

    old_usage =
      Enum.reduce(old_messages, %Usage{}, fn msg, acc ->
        if msg[:usage], do: Usage.add(acc, msg.usage), else: acc
      end)

    summary_text = build_summary_text(old_messages, predict_opts)

    summary_msg = %{
      role: :assistant,
      blocks: [{:text, summary_text}],
      usage: old_usage
    }

    new_messages = [summary_msg | recent]
    :ok = Session.replace_messages(session, new_messages)
    {:ok, length(old_messages)}
  end

  defp build_summary_text(old_messages, predict_opts) do
    case build_summary(old_messages, predict_opts) do
      {:ok, summary_text} ->
        summary_text

      {:error, reason} ->
        Logger.warning(
          "LLM compaction failed, falling back to text extraction: #{inspect(reason)}"
        )

        build_fallback_summary(old_messages)
    end
  end

  defp build_summary(messages, predict_opts) do
    inputs = %{"conversation" => format_messages_for_summary(messages)}

    opts =
      predict_opts
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Keyword.put(:system, "You are a conversation summarizer.")

    with {:ok, outputs} <- Predict.call(summary_signature(), inputs, opts) do
      {:ok, render_summary(outputs)}
    end
  end

  @spec summary_signature() :: Signature.t()
  def summary_signature do
    Signature.new!(@summary_spec, name: "summary", instructions: @summary_instructions)
  end

  @spec render_summary(map()) :: String.t()
  def render_summary(outputs) do
    sections =
      [
        {"Files", outputs["files"]},
        {"Decisions", outputs["decisions"]},
        {"Open tasks", outputs["open_tasks"]},
        {"Errors", outputs["errors"]}
      ]
      |> Enum.reject(fn {_title, items} -> items in [nil, []] end)
      |> Enum.map_join("\n\n", fn {title, items} ->
        "## #{title}\n" <> Enum.map_join(items, "\n", &("- " <> &1))
      end)

    body = [outputs["summary"], sections] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join("\n\n")
    "[Conversation summary]\n#{body}\n[End of summary - recent messages follow]"
  end

  defp format_messages_for_summary(messages) do
    Enum.map_join(messages, "\n", fn msg ->
      role = Atom.to_string(msg.role)
      blocks_text = Enum.map_join(msg.blocks, "\n", &block_text/1)
      "[#{role}]: #{blocks_text}"
    end)
  end

  defp build_fallback_summary(messages) do
    conversation_text = format_messages_for_summary(messages)

    "[Previous conversation summary]\n#{conversation_text}\n[End of summary - recent messages follow]"
  end

  defp block_chars({:text, text}), do: String.length(text)

  defp block_chars({:tool_use, _, _, input}) when is_binary(input),
    do: String.length(input) + 20

  defp block_chars({:tool_use, _, _, input}) when is_map(input),
    do: input |> Jason.encode!() |> byte_size() |> Kernel.+(20)

  defp block_chars({:tool_result, _, _, output, _, _}), do: String.length(output) + 20
  defp block_chars(_), do: 0

  defp block_text({:text, text}), do: text
  defp block_text({:tool_use, _id, name, _input}), do: "[used tool: #{name}]"

  defp block_text({:tool_result, _id, name, output, _err, :ok}),
    do: "[#{name} result: #{String.slice(output, 0, 200)}]"

  defp block_text({:tool_result, _id, name, output, _err, outcome}),
    do: "[#{name} #{outcome}: #{String.slice(output, 0, 200)}]"

  defp block_text(_), do: ""
end
