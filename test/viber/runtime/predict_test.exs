defmodule Viber.Runtime.PredictTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.{Predict, Signature}
  alias Viber.Runtime.Signature.ParseError
  alias Viber.ScriptedProvider

  @sig Signature.new!("question -> answer: int, why", name: "answer")

  defp tool_use(input),
    do: %{"type" => "tool_use", "id" => "t1", "name" => "submit_answer", "input" => input}

  test "forces the submit tool and returns validated outputs" do
    ScriptedProvider.script([
      ScriptedProvider.response([tool_use(%{"answer" => 4, "why" => "2+2"})])
    ])

    assert {:ok, %{"answer" => 4, "why" => "2+2"}} =
             Predict.call(@sig, %{question: "2+2?"},
               model: "claude-sonnet-5",
               provider_module: ScriptedProvider
             )

    [request] = ScriptedProvider.requests()
    assert request.tool_choice == {:tool, "submit_answer"}
    assert [%{name: "submit_answer"}] = request.tools
    assert request.thinking == %{type: "disabled"}
    assert [%{content: [%{text: text}]}] = request.messages
    assert text =~ "<question>\n2+2?\n</question>"
  end

  test "retries once with the parse error, answering the tool call" do
    ScriptedProvider.script([
      ScriptedProvider.response([tool_use(%{"answer" => "four"})]),
      ScriptedProvider.response([tool_use(%{"answer" => 4, "why" => "math"})])
    ])

    assert {:ok, %{"answer" => 4}} =
             Predict.call(@sig, %{question: "2+2?"},
               model: "gpt-4o",
               provider_module: ScriptedProvider
             )

    [_, retry] = ScriptedProvider.requests()
    [_user, assistant, feedback] = retry.messages
    assert assistant.role == "assistant"

    assert [%{type: "tool_result", tool_use_id: "t1", is_error: true, content: [%{text: msg}]}] =
             feedback.content

    assert msg =~ "missing fields: why"
  end

  test "gives up after max_retries" do
    bad = ScriptedProvider.response([tool_use(%{"answer" => "x", "why" => "y"})])
    ScriptedProvider.script([bad, bad])

    assert {:error, %ParseError{kind: :invalid_fields, fields: ["answer"]}} =
             Predict.call(@sig, %{question: "?"},
               model: "gpt-4o",
               provider_module: ScriptedProvider
             )
  end

  test "accepts JSON in text when no tool was called" do
    ScriptedProvider.script([
      ScriptedProvider.response([%{type: "text", text: ~s(Here: {"answer": 1, "why": "w"})}])
    ])

    assert {:ok, %{"answer" => 1}} =
             Predict.call(@sig, %{question: "?"},
               model: "ollama:qwen3.8:latest",
               provider_module: ScriptedProvider
             )

    assert [%{tool_choice: nil}] = ScriptedProvider.requests()
  end

  test "no tool call and no JSON is :no_tool_call" do
    ScriptedProvider.script([ScriptedProvider.response([%{type: "text", text: "dunno"}])])

    assert {:error, %ParseError{kind: :no_tool_call}} =
             Predict.call(@sig, %{question: "?"},
               model: "gpt-4o",
               provider_module: ScriptedProvider,
               max_retries: 0
             )
  end

  test "API errors pass through" do
    ScriptedProvider.script([{:error, %Viber.API.Error{type: :api, message: "down"}}])

    assert {:error, %Viber.API.Error{message: "down"}} =
             Predict.call(@sig, %{question: "?"},
               model: "gpt-4o",
               provider_module: ScriptedProvider
             )
  end

  test "tool_choice/2 falls back where forcing is not allowed" do
    assert Predict.tool_choice("claude-opus-5", "submit_x") == {:tool, "submit_x"}
    assert Predict.tool_choice("fable", "submit_x") == :auto
    assert Predict.tool_choice("ollama:llama3", "submit_x") == nil
  end
end
