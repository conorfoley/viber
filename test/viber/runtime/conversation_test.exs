defmodule Viber.Runtime.ConversationTest do
  use ExUnit.Case, async: true

  alias Viber.API.{MessageResponse, Usage}
  alias Viber.Runtime.{Config, Conversation, Session}

  defmodule TextOnlyProvider do
    @behaviour Viber.API.Provider

    @impl true
    def send_message(_request), do: {:error, %Viber.API.Error{type: :api, message: "use stream"}}

    @impl true
    def stream_message(_request) do
      events = [
        {:message_start,
         %MessageResponse{
           id: "msg_1",
           type: "message",
           role: "assistant",
           content: [],
           model: "test",
           usage: %Usage{input_tokens: 10, output_tokens: 5}
         }},
        {:content_block_start, 0, %{type: "text", text: ""}},
        {:content_block_delta, 0, %{type: "text_delta", text: "Hello "}},
        {:content_block_delta, 0, %{type: "text_delta", text: "world!"}},
        {:content_block_stop, 0},
        {:message_delta, %{"stop_reason" => "end_turn"},
         %Usage{input_tokens: 10, output_tokens: 5}},
        :message_stop
      ]

      {:ok, events}
    end
  end

  defmodule ToolUseProvider do
    @behaviour Viber.API.Provider

    @impl true
    def send_message(_request), do: {:error, %Viber.API.Error{type: :api, message: "use stream"}}

    @impl true
    def stream_message(_request) do
      turn = Process.get(:turn_count, 0)
      Process.put(:turn_count, turn + 1)

      if turn == 0 do
        tool_name = Process.get(:tool_name, "bash")

        events = [
          {:message_start,
           %MessageResponse{
             id: "msg_2",
             type: "message",
             role: "assistant",
             content: [],
             model: "test",
             usage: %Usage{input_tokens: 20, output_tokens: 10}
           }},
          {:content_block_start, 0, %{type: "tool_use", id: "tu_1", name: tool_name}},
          {:content_block_delta, 0, %{type: "input_json_delta", partial_json: "{\"command\":"}},
          {:content_block_delta, 0, %{type: "input_json_delta", partial_json: "\"echo hi\"}"}},
          {:content_block_stop, 0},
          {:message_delta, %{"stop_reason" => "tool_use"},
           %Usage{input_tokens: 20, output_tokens: 10}},
          :message_stop
        ]

        {:ok, events}
      else
        events = [
          {:message_start,
           %MessageResponse{
             id: "msg_3",
             type: "message",
             role: "assistant",
             content: [],
             model: "test",
             usage: %Usage{input_tokens: 30, output_tokens: 8}
           }},
          {:content_block_start, 0, %{type: "text", text: ""}},
          {:content_block_delta, 0, %{type: "text_delta", text: "Done!"}},
          {:content_block_stop, 0},
          {:message_delta, %{"stop_reason" => "end_turn"},
           %Usage{input_tokens: 30, output_tokens: 8}},
          :message_stop
        ]

        {:ok, events}
      end
    end
  end

  defmodule CaptureToolsProvider do
    @behaviour Viber.API.Provider

    @impl true
    def send_message(_request), do: {:error, %Viber.API.Error{type: :api, message: "use stream"}}

    @impl true
    def stream_message(request) do
      send(Process.get(:captured_tool_names), Enum.map(request.tools, & &1.name))
      TextOnlyProvider.stream_message(request)
    end
  end

  test "simple text response - single turn" do
    {:ok, session} = Session.start_link(id: "conv-1")

    events = :ets.new(:events, [:bag, :public])

    handler = fn event ->
      :ets.insert(events, {System.monotonic_time(), event})
    end

    result =
      Conversation.run(
        session: session,
        model: "test",
        user_input: "hi",
        event_handler: handler,
        provider_module: TextOnlyProvider,
        project_root: System.tmp_dir!(),
        permission_mode: :allow
      )

    assert {:ok, %{text: "Hello world!", iterations: 1}} = result

    recorded = :ets.tab2list(events) |> Enum.map(fn {_, e} -> e end)

    assert Enum.any?(recorded, fn e ->
             match?(%Viber.Runtime.Event{type: :text_delta, payload: %{text: "Hello "}}, e)
           end)

    assert Enum.any?(recorded, fn e ->
             match?(%Viber.Runtime.Event{type: :turn_complete}, e)
           end)

    messages = Session.get_messages(session)
    assert length(messages) == 2
    :ets.delete(events)
  end

  test "disabled subagents are not offered to the model" do
    Process.put(:captured_tool_names, self())
    {:ok, session} = Session.start_link(id: "conv-no-subagents")

    assert {:ok, %{text: "Hello world!"}} =
             Conversation.run(
               session: session,
               model: "ollama:qwen3.8:latest",
               config: %Config{enable_subagents: false},
               user_input: "hi",
               provider_module: CaptureToolsProvider,
               project_root: System.tmp_dir!(),
               permission_mode: :allow
             )

    assert_receive tool_names when is_list(tool_names)
    refute "spawn_agent" in tool_names
  after
    Process.delete(:captured_tool_names)
  end

  test "disabled subagents cannot run even if the model returns a spawn call" do
    Process.put(:turn_count, 0)
    Process.put(:tool_name, "spawn_agent")
    {:ok, session} = Session.start_link(id: "conv-no-spawn-run")
    events = :ets.new(:disabled_subagent_events, [:bag, :public])

    result =
      Conversation.run(
        session: session,
        model: "ollama:qwen3.8:latest",
        config: %Config{enable_subagents: false},
        user_input: "delegate this",
        provider_module: ToolUseProvider,
        event_handler: fn event -> :ets.insert(events, {System.monotonic_time(), event}) end,
        project_root: System.tmp_dir!(),
        permission_mode: :allow
      )

    assert {:ok, %{text: "Done!"}} = result

    recorded = :ets.tab2list(events) |> Enum.map(fn {_, event} -> event end)

    assert Enum.any?(recorded, fn
             %Viber.Runtime.Event{
               type: :tool_result,
               payload: %{name: "spawn_agent", is_error: true, outcome: :refused, output: output}
             } ->
               output =~ "disabled"

             _ ->
               false
           end)
  after
    Process.delete(:turn_count)
    Process.delete(:tool_name)
  end

  test "tool use triggers execution and follow-up turn" do
    Process.put(:turn_count, 0)
    {:ok, session} = Session.start_link(id: "conv-2")

    result =
      Conversation.run(
        session: session,
        model: "test",
        user_input: "run echo",
        provider_module: ToolUseProvider,
        project_root: System.tmp_dir!(),
        permission_mode: :allow
      )

    assert {:ok, %{text: "Done!", iterations: 2}} = result

    messages = Session.get_messages(session)
    assert length(messages) == 4

    assert Enum.any?(messages, fn msg ->
             match?([{:tool_result, _, _, _, false, :ok}], msg.blocks)
           end)
  end

  defmodule StreamErrorDuringToolProvider do
    @behaviour Viber.API.Provider

    @impl true
    def send_message(_request), do: {:error, %Viber.API.Error{type: :api, message: "use stream"}}

    @impl true
    def stream_message(_request) do
      events = [
        {:message_start,
         %MessageResponse{
           id: "msg_err",
           type: "message",
           role: "assistant",
           content: [],
           model: "test",
           usage: %Usage{input_tokens: 10, output_tokens: 5}
         }},
        {:content_block_start, 0, %{type: "tool_use", id: "tu_err", name: "write_file"}},
        {:content_block_delta, 0,
         %{
           type: "input_json_delta",
           partial_json: "{\"path\":\"/some.icls\",\"content\":\"...TRUNCATED"
         }},
        {:stream_error, %RuntimeError{message: "transport timeout"}}
      ]

      {:ok, events}
    end
  end

  test "stream error during tool call returns error without executing tool" do
    {:ok, session} = Session.start_link(id: "conv-stream-err")

    events = :ets.new(:stream_err_events, [:bag, :public])

    handler = fn event ->
      :ets.insert(events, {System.monotonic_time(), event})
    end

    result =
      Conversation.run(
        session: session,
        model: "test",
        user_input: "write a big file",
        event_handler: handler,
        provider_module: StreamErrorDuringToolProvider,
        project_root: System.tmp_dir!(),
        permission_mode: :allow
      )

    assert {:error, {:stream_error, _}} = result

    recorded = :ets.tab2list(events) |> Enum.map(fn {_, e} -> e end)
    assert Enum.any?(recorded, fn e -> match?(%Viber.Runtime.Event{type: :error}, e) end)

    refute Enum.any?(recorded, fn e ->
             match?(
               %Viber.Runtime.Event{type: :tool_result, payload: %{name: "write_file"}},
               e
             )
           end)

    :ets.delete(events)
  end

  test "permission denial returns error in tool result" do
    {:ok, session} = Session.start_link(id: "conv-3")
    Process.put(:turn_count, 0)

    events = :ets.new(:deny_events, [:bag, :public])

    handler = fn event ->
      :ets.insert(events, {System.monotonic_time(), event})
    end

    Conversation.run(
      session: session,
      model: "test",
      user_input: "run bash",
      provider_module: ToolUseProvider,
      event_handler: handler,
      project_root: System.tmp_dir!(),
      permission_mode: :read_only
    )

    recorded = :ets.tab2list(events) |> Enum.map(fn {_, e} -> e end)

    assert Enum.any?(recorded, fn e ->
             match?(
               %Viber.Runtime.Event{
                 type: :tool_result,
                 payload: %{name: "bash", is_error: true, outcome: :refused}
               },
               e
             )
           end)

    assert Enum.any?(Session.get_messages(session), fn msg ->
             match?([{:tool_result, _, "bash", _, true, :refused}], msg.blocks)
           end)

    :ets.delete(events)
  end

  describe "terminal tools" do
    setup do
      sig = Viber.Runtime.Signature.new!("-> answer: int", name: "answer")
      {:ok, session} = Session.start_link(id: "conv-terminal-#{System.unique_integer()}")
      events = :ets.new(:terminal_events, [:bag, :public])

      run = fn ->
        Conversation.run(
          session: session,
          model: "test",
          user_input: "answer",
          provider_module: Viber.ScriptedProvider,
          event_handler: fn e -> :ets.insert(events, {System.monotonic_time(), e}) end,
          project_root: System.tmp_dir!(),
          permission_mode: :allow,
          terminal_tools: [sig]
        )
      end

      {:ok, run: run, session: session, events: events}
    end

    test "a valid submission ends the run with its outputs", %{run: run, session: session} do
      Viber.ScriptedProvider.script_stream([
        [{:text, "ok"}, {:tool, "s1", "submit_answer", %{"answer" => 42}}]
      ])

      assert {:ok, %{text: "ok", iterations: 1, submitted: %{"answer" => %{"answer" => 42}}}} =
               run.()

      [request] = Viber.ScriptedProvider.requests()
      assert "submit_answer" in Enum.map(request.tools, & &1.name)

      assert [_, _, %{blocks: [{:tool_result, "s1", "submit_answer", "Submitted.", false, :ok}]}] =
               Session.get_messages(session)
    end

    test "an invalid submission is returned as a tool error and the loop continues", %{
      run: run,
      events: events
    } do
      Viber.ScriptedProvider.script_stream([
        [{:tool, "s1", "submit_answer", %{"answer" => "many"}}],
        [{:tool, "s2", "submit_answer", %{"answer" => 7}}]
      ])

      assert {:ok, %{iterations: 2, submitted: %{"answer" => %{"answer" => 7}}}} = run.()

      recorded = :ets.tab2list(events) |> Enum.map(fn {_, e} -> e end)

      assert Enum.any?(recorded, fn
               %Viber.Runtime.Event{
                 type: :tool_result,
                 payload: %{id: "s1", outcome: :error, output: output}
               } ->
                 output =~ "answer must be an integer"

               _ ->
                 false
             end)
    end

    test "regular tools in the same turn still run, in call order", %{
      run: run,
      session: session
    } do
      Viber.ScriptedProvider.script_stream([
        [
          {:tool, "b1", "bash", %{"command" => "echo side"}},
          {:tool, "s1", "submit_answer", %{"answer" => 1}}
        ]
      ])

      assert {:ok, %{submitted: %{"answer" => %{"answer" => 1}}}} = run.()

      [_, _, %{blocks: blocks}] = Session.get_messages(session)

      assert [{:tool_result, "b1", "bash", out, false, :ok}, {:tool_result, "s1", _, _, _, :ok}] =
               blocks

      assert out =~ "side"
    end

    test "without a submission the run ends normally", %{run: run} do
      Viber.ScriptedProvider.script_stream([[{:text, "no tool"}]])
      assert {:ok, result} = run.()
      refute Map.has_key?(result, :submitted)
    end
  end

  describe "run events" do
    setup do
      {:ok, session} = Session.start_link(id: "conv-run-events-#{System.unique_integer()}")
      parent = self()

      run = fn opts ->
        Conversation.run(
          Keyword.merge(
            [
              session: session,
              model: "test",
              user_input: "hi",
              provider_module: Viber.ScriptedProvider,
              event_handler: fn e -> send(parent, {:run_event, e}) end,
              project_root: System.tmp_dir!(),
              permission_mode: :allow,
              origin: :server
            ],
            opts
          )
        )
      end

      {:ok, run: run}
    end

    defp drain_events(acc \\ []) do
      receive do
        {:run_event, e} -> drain_events([e | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end

    test "a completed run is framed by run_started and run_finished", %{run: run} do
      Viber.ScriptedProvider.script_stream([
        [{:tool, "b1", "bash", %{"command" => "echo hi"}}],
        [{:text, "done"}]
      ])

      assert {:ok, %{iterations: 2}} = run.([])
      events = drain_events()
      types = Enum.map(events, & &1.type)

      assert hd(types) == :run_started
      assert Enum.take(types, -2) == [:run_finished, :turn_complete]
      assert Enum.count(types, &(&1 == :model_request)) == 2
      assert Enum.count(types, &(&1 == :model_response)) == 2

      [%{run_id: run_id} | _] = events
      assert "run_" <> _ = run_id
      assert Enum.all?(events, &(&1.run_id == run_id))
      assert Enum.map(events, & &1.seq) == Enum.to_list(1..length(events))

      assert %{payload: %{origin: :server, model: "test", parent_run_id: nil}} = hd(events)

      assert [%{payload: %{stop_reason: "end_turn", tool_calls: 1, iteration: 0}}, _] =
               Enum.filter(events, &(&1.type == :model_response))

      assert %{payload: %{termination_reason: :completed, termination_cause: nil, iterations: 2}} =
               Enum.find(events, &(&1.type == :run_finished))
    end

    test "a provider error finishes the run before the error event", %{run: run} do
      Viber.ScriptedProvider.script_stream([])

      assert {:error, _} = run.([])
      events = drain_events()
      assert Enum.take(Enum.map(events, & &1.type), -2) == [:run_finished, :error]

      assert %{payload: %{termination_reason: :error, termination_cause: %{kind: "api_error"}}} =
               Enum.find(events, &(&1.type == :run_finished))
    end

    test "max iterations is reported as the termination reason", %{run: run} do
      Viber.ScriptedProvider.script_stream([[{:tool, "b1", "bash", %{"command" => "true"}}]])

      assert {:error, :max_iterations} = run.(max_iterations: 1)
      events = drain_events()
      assert Enum.take(Enum.map(events, & &1.type), -2) == [:run_finished, :error]

      assert %{payload: %{termination_reason: :max_iterations, iterations: 1}} =
               Enum.find(events, &(&1.type == :run_finished))
    end

    test "a terminal submission finishes with :submitted", %{run: run} do
      sig = Viber.Runtime.Signature.new!("-> answer: int", name: "answer")

      Viber.ScriptedProvider.script_stream([
        [{:tool, "s1", "submit_answer", %{"answer" => 1}}]
      ])

      assert {:ok, %{submitted: _}} = run.(terminal_tools: [sig])

      assert %{payload: %{termination_reason: :submitted}} =
               Enum.find(drain_events(), &(&1.type == :run_finished))
    end

    test "the given run_id and parent_run_id are used", %{run: run} do
      Viber.ScriptedProvider.script_stream([[{:text, "ok"}]])
      assert {:ok, _} = run.(run_id: "run_fixed", parent_run_id: "run_parent")

      [first | _] = events = drain_events()
      assert Enum.all?(events, &(&1.run_id == "run_fixed"))
      assert first.payload.parent_run_id == "run_parent"
    end
  end
end
