defmodule Viber.Runtime.SubAgentTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.Conversation.Context
  alias Viber.Runtime.SubAgent
  alias Viber.ScriptedProvider

  defp parent_ctx do
    %Context{
      session: self(),
      model: "test",
      event_handler: fn _ -> :ok end,
      provider_module: ScriptedProvider,
      permission_mode: :allow,
      project_root: System.tmp_dir!()
    }
  end

  test "a reviewer's submitted verdict is returned and rendered" do
    ScriptedProvider.script_stream([
      [
        {:text, "Checked."},
        {:tool, "v1", "submit_verdict",
         %{"verdict" => "failed", "justification" => "tests fail", "evidence" => ["mix test"]}}
      ]
    ])

    assert {:ok, %{verdict: %{"verdict" => "failed"}, text: text}} =
             SubAgent.run(%{"task" => "review", "role" => "reviewer"}, parent_ctx())

    assert text == "Checked.\n\nVERDICT: failed\n\ntests fail\n\n- mix test"

    [request] = ScriptedProvider.requests()
    assert "submit_verdict" in Enum.map(request.tools, & &1.name)
  end

  test "a reviewer without a submission falls back to the VERDICT line" do
    ScriptedProvider.script_stream([[{:text, "All good.\nVERDICT: Passed"}]])

    assert {:ok, %{verdict: %{"verdict" => "passed"}}} =
             SubAgent.run(%{"task" => "review", "role" => "reviewer"}, parent_ctx())
  end

  test "workers get no submit tool and no verdict" do
    ScriptedProvider.script_stream([[{:text, "done"}]])

    assert {:ok, result} = SubAgent.run(%{"task" => "work"}, parent_ctx())
    assert result == %{text: "done", iterations: 1}

    [request] = ScriptedProvider.requests()
    refute "submit_verdict" in Enum.map(request.tools, & &1.name)
  end

  test "parse_verdict_line/1 takes the last verdict" do
    assert SubAgent.parse_verdict_line("VERDICT: failed\nlater\nVERDICT: passed") == "passed"
    assert SubAgent.parse_verdict_line("no verdict") == nil
  end
end
