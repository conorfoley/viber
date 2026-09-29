defmodule Viber.Runtime.Predict do
  @moduledoc """
  Typed, one-shot model calls against a `Viber.Runtime.Signature`.

  `call/3` sends the signature's inputs and offers a single
  `submit_<name>` tool whose schema is the signature's outputs. Where the
  provider allows it the tool is forced (`tool_choice: {:tool, name}`) and
  thinking is turned off; on models whose thinking cannot be disabled
  (Fable 5, Mythos 5) the choice falls back to `:auto`, and Ollama gets no
  `tool_choice`. Without a tool call, a JSON object in the reply text is
  accepted.

  A reply that does not fit the signature is sent back to the model with
  the `Viber.Runtime.Signature.ParseError` message, up to `:max_retries`
  times (default 1).

  Options:

    * `:model` (required)
    * `:system` — system prompt
    * `:max_tokens` — default 4096
    * `:max_retries` — default 1
    * `:provider_module` — call this `Viber.API.Provider` directly
      instead of `Viber.API.Client`
    * `:client_opts` — passed to `Viber.API.Client.send_message/3`
  """

  alias Viber.API.{Client, Error, InputMessage, MessageRequest, MessageResponse}
  alias Viber.Runtime.Signature
  alias Viber.Runtime.Signature.ParseError

  @default_system "Answer by calling the submit tool exactly once with every field filled in."
  @always_thinking ~w[claude-fable claude-mythos]

  @spec call(Signature.t(), map(), keyword()) ::
          {:ok, map()} | {:error, ParseError.t() | Error.t() | term()}
  def call(%Signature{} = signature, inputs, opts) when is_map(inputs) do
    resolved = opts |> Keyword.fetch!(:model) |> Client.resolve_model_alias()

    request = %MessageRequest{
      model: resolved,
      max_tokens: Keyword.get(opts, :max_tokens, 4_096),
      messages: [InputMessage.user_text(prompt(signature, inputs))],
      system: Keyword.get(opts, :system, @default_system),
      tools: [Signature.tool_definition(signature)],
      tool_choice: tool_choice(resolved, Signature.tool_name(signature)),
      thinking: Client.thinking_config(resolved, "off"),
      stream: false
    }

    attempt(signature, request, opts, Keyword.get(opts, :max_retries, 1))
  end

  @spec tool_choice(String.t(), String.t()) :: :auto | {:tool, String.t()} | nil
  def tool_choice(model, tool_name) do
    canonical = Client.resolve_model_alias(model)

    cond do
      String.starts_with?(canonical, "ollama:") -> nil
      Enum.any?(@always_thinking, &String.starts_with?(canonical, &1)) -> :auto
      true -> {:tool, tool_name}
    end
  end

  @spec extract(Signature.t(), MessageResponse.t()) ::
          {:ok, map()} | {:error, ParseError.t()}
  def extract(%Signature{} = signature, %MessageResponse{content: content}) do
    blocks = Enum.map(content, &normalize_block/1)
    name = Signature.tool_name(signature)

    case Enum.find(blocks, &match?(%{type: "tool_use", name: ^name}, &1)) do
      %{input: input} ->
        validate_input(signature, input)

      nil ->
        from_text(signature, blocks)
    end
  end

  defp attempt(signature, request, opts, retries_left) do
    with {:ok, response} <- send_request(request, opts) do
      case extract(signature, response) do
        {:ok, outputs} ->
          {:ok, outputs}

        {:error, %ParseError{} = error} when retries_left > 0 ->
          request = %{
            request
            | messages: request.messages ++ feedback(signature, response, error)
          }

          attempt(signature, request, opts, retries_left - 1)

        {:error, _} = error ->
          error
      end
    end
  end

  defp send_request(request, opts) do
    case Keyword.get(opts, :provider_module) do
      nil -> Client.send_message(request.model, request, Keyword.get(opts, :client_opts, []))
      module -> module.send_message(request)
    end
  end

  defp prompt(%Signature{instructions: instructions} = signature, inputs) do
    body = Signature.format_inputs(signature, inputs)
    call = "Call #{Signature.tool_name(signature)} with your answer."

    [instructions, body, call]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp feedback(signature, response, error) do
    blocks =
      response.content
      |> Enum.map(&normalize_block/1)
      |> Enum.filter(&(&1.type in ["text", "thinking", "redacted_thinking", "tool_use"]))

    assistant = %InputMessage{role: "assistant", content: blocks}

    message =
      "Your answer did not fit: #{error.message}. Call #{Signature.tool_name(signature)} again."

    case Enum.filter(blocks, &(&1.type == "tool_use")) do
      [] ->
        [assistant, InputMessage.user_text(message)]

      tool_uses ->
        results =
          Enum.map(tool_uses, fn %{id: id} ->
            %{
              type: "tool_result",
              tool_use_id: id,
              content: [%{type: "text", text: message}],
              is_error: true
            }
          end)

        [assistant, %InputMessage{role: "user", content: results}]
    end
  end

  defp validate_input(signature, input) when is_binary(input) do
    case Jason.decode(input) do
      {:ok, map} when is_map(map) -> Signature.validate(signature, map)
      _ -> {:error, ParseError.new(:malformed, "tool input is not a JSON object", raw: input)}
    end
  end

  defp validate_input(signature, input), do: Signature.validate(signature, input)

  defp from_text(signature, blocks) do
    text =
      blocks
      |> Enum.filter(&(&1.type == "text"))
      |> Enum.map_join("\n", & &1.text)

    case Signature.decode(signature, text) do
      {:ok, outputs} ->
        {:ok, outputs}

      {:error, %ParseError{kind: :malformed}} ->
        {:error,
         ParseError.new(
           :no_tool_call,
           "the model did not call #{Signature.tool_name(signature)}",
           raw: text
         )}

      {:error, _} = error ->
        error
    end
  end

  defp normalize_block(block) when is_map(block) do
    type = get(block, :type)

    case type do
      "text" ->
        %{type: "text", text: get(block, :text) || ""}

      "thinking" ->
        %{type: "thinking", thinking: get(block, :thinking), signature: get(block, :signature)}

      "redacted_thinking" ->
        %{type: "redacted_thinking", data: get(block, :data)}

      "tool_use" ->
        %{
          type: "tool_use",
          id: get(block, :id),
          name: get(block, :name),
          input: get(block, :input) || %{}
        }

      other ->
        %{type: other}
    end
  end

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
