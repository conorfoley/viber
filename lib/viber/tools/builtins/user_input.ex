defmodule Viber.Tools.Builtins.UserInput do
  @moduledoc """
  Prompt the user for input during a conversation turn.

  Displays a question (and optional choices) to the user via the terminal,
  then blocks until the user responds. This allows the LLM to ask
  clarifying questions mid-execution rather than guessing.
  """

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"question" => question} = input) do
    options = input["options"] || []

    prompt = build_prompt(question, options)

    case IO.gets(prompt) do
      :eof ->
        {:error, "No input received (EOF)"}

      {:error, reason} ->
        {:error, "Failed to read input: #{inspect(reason)}"}

      raw ->
        answer = String.trim(raw)

        if answer == "" do
          {:error, "No answer provided"}
        else
          {:ok, answer}
        end
    end
  end

  def execute(_), do: {:error, "Missing required parameter: question"}

  defp build_prompt(question, []) do
    [
      IO.ANSI.cyan(),
      "\n? ",
      IO.ANSI.bright(),
      question,
      IO.ANSI.reset(),
      "\n> "
    ]
  end

  defp build_prompt(question, options) when is_list(options) do
    numbered =
      options
      |> Enum.with_index(1)
      |> Enum.map(fn {opt, idx} ->
        [IO.ANSI.faint(), "  #{idx}. ", IO.ANSI.reset(), opt, "\n"]
      end)

    [
      IO.ANSI.cyan(),
      "\n? ",
      IO.ANSI.bright(),
      question,
      IO.ANSI.reset(),
      "\n",
      numbered,
      "> "
    ]
  end
end
