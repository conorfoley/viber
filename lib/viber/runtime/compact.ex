defmodule Viber.Runtime.Compact do
  @moduledoc """
  Conversation history compaction via LLM summarization.
  """

  require Logger

  alias Viber.API.{Client, MessageRequest}
  alias Viber.Runtime.Session

  @chars_per_token 4
  @default_token_threshold 100_000
  @preserve_recent 4

  @summary_prompt """
  Summarize the conversation above into a concise but thorough reference document.
  Preserve: all file paths mentioned, key decisions made, tool calls and their outcomes,
  code changes applied, errors encountered, and any unresolved tasks.
  Omit: verbatim code blocks (reference by file path instead), redundant greetings,
  and tool call input/output that is no longer relevant.
  Format as a structured summary with sections. Be concise but do not lose important context.
  """

  @spec should_compact?(GenServer.server(), keyword()) :: boolean()
  def should_compact?(session, opts \\ []) do
    threshold = Keyword.get(opts, :token_threshold, @default_token_threshold)
    messages = Session.get_messages(session)
    compactable = Enum.drop(messages, -@preserve_recent)

    length(compactable) > 0 and estimate_tokens(compactable) >= threshold
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

  @spec compact(GenServer.server(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def compact(session, opts \\ []) do
    messages = Session.get_messages(session)
    preserve = Keyword.get(opts, :preserve_recent, @preserve_recent)
    model = Keyword.get(opts, :model, "sonnet")

    if length(messages) <= preserve do
      {:ok, 0}
    else
      {old_messages, recent} = Enum.split(messages, length(messages) - preserve)

      case build_summary(old_messages, model) do
        {:ok, summary_text} ->
          summary_msg = %{
            role: :user,
            blocks: [{:text, summary_text}],
            usage: nil
          }

          new_messages = [summary_msg | recent]
          :ok = Session.replace_messages(session, new_messages)
          {:ok, length(old_messages)}

        {:error, reason} ->
          Logger.warning(
            "LLM compaction failed, falling back to text extraction: #{inspect(reason)}"
          )

          fallback_text = build_fallback_summary(old_messages)

          summary_msg = %{
            role: :user,
            blocks: [{:text, fallback_text}],
            usage: nil
          }

          new_messages = [summary_msg | recent]
          :ok = Session.replace_messages(session, new_messages)
          {:ok, length(old_messages)}
      end
    end
  end

  defp build_summary(messages, model) do
    conversation_text = format_messages_for_summary(messages)

    request = %MessageRequest{
      model: Client.resolve_model_alias(model),
      max_tokens: 4_096,
      messages: [
        %Viber.API.InputMessage{
          role: "user",
          content: [%{type: "text", text: conversation_text <> "\n\n" <> @summary_prompt}]
        }
      ],
      system: "You are a conversation summarizer. Produce a concise structured summary.",
      tools: [],
      stream: false
    }

    case Client.send_message(model, request) do
      {:ok, response} ->
        text =
          response.content
          |> Enum.filter(fn c -> c["type"] == "text" || Map.get(c, :type) == "text" end)
          |> Enum.map_join("\n", fn c -> c["text"] || Map.get(c, :text, "") end)

        {:ok, "[Conversation summary]\n#{text}\n[End of summary - recent messages follow]"}

      {:error, _} = err ->
        err
    end
  end

  defp format_messages_for_summary(messages) do
    messages
    |> Enum.map(fn msg ->
      role = Atom.to_string(msg.role)
      blocks_text = Enum.map_join(msg.blocks, "\n", &block_text/1)
      "[#{role}]: #{blocks_text}"
    end)
    |> Enum.join("\n")
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

  defp block_chars({:tool_result, _, _, output, _}), do: String.length(output) + 20
  defp block_chars(_), do: 0

  defp block_text({:text, text}), do: text
  defp block_text({:tool_use, _id, name, _input}), do: "[used tool: #{name}]"

  defp block_text({:tool_result, _id, name, output, _err}),
    do: "[#{name} result: #{String.slice(output, 0, 200)}]"

  defp block_text(_), do: ""
end
