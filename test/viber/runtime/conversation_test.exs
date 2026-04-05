defmodule Viber.Runtime.ConversationTest do
  use ExUnit.Case, async: true

  alias Viber.API.{MessageResponse, Usage}
  alias Viber.Runtime.{Conversation, Session}

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
          {:content_block_start, 0, %{type: "tool_use", id: "tu_1", name: "bash"}},
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
    assert Enum.any?(recorded, fn e -> match?({:text_delta, "Hello "}, e) end)
    assert Enum.any?(recorded, fn e -> match?({:turn_complete, _}, e) end)

    messages = Session.get_messages(session)
    assert length(messages) == 2
    :ets.delete(events)
  end

  test "tool use triggers execution and follow-up turn" do
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
    assert Enum.any?(recorded, fn e -> match?({:error, _}, e) end)
    refute Enum.any?(recorded, fn e -> match?({:tool_result, "write_file", _, _}, e) end)

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
    assert Enum.any?(recorded, fn e -> match?({:tool_result, "bash", _, true}, e) end)
    :ets.delete(events)
  end
end
