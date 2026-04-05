defmodule Viber.Runtime.Compact do
  @moduledoc """
  Conversation history compaction via summarization.
  """

  alias Viber.Runtime.Session

  @chars_per_token 4
  @default_token_threshold 100_000
  @preserve_recent 4

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

    if length(messages) <= preserve do
      {:ok, 0}
    else
      {old_messages, recent} = Enum.split(messages, length(messages) - preserve)
      summary_text = build_summary(old_messages)

      summary_msg = %{
        role: :user,
        blocks: [{:text, summary_text}],
        usage: nil
      }

      new_messages = [summary_msg | recent]
      :ok = Session.replace_messages(session, new_messages)
      {:ok, length(old_messages)}
    end
  end

  defp build_summary(messages) do
    conversation_text =
      messages
      |> Enum.map(fn msg ->
        role = Atom.to_string(msg.role)
        blocks_text = Enum.map_join(msg.blocks, "\n", &block_text/1)
        "[#{role}]: #{blocks_text}"
      end)
      |> Enum.join("\n")

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
