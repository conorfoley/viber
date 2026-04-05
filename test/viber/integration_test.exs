defmodule Viber.IntegrationTest do
  use ExUnit.Case, async: false

  alias Viber.API.{MessageResponse, Usage}
  alias Viber.Runtime.{Compact, Conversation, Session}
  alias Viber.Commands.{Parser, Registry}
  alias Viber.CLI.Renderer

  defmodule SimpleProvider do
    @behaviour Viber.API.Provider

    @impl true
    def send_message(_request),
      do: {:error, %Viber.API.Error{type: :api, message: "use stream"}}

    @impl true
    def stream_message(_request) do
      events = [
        {:message_start,
         %MessageResponse{
           id: "int_1",
           type: "message",
           role: "assistant",
           content: [],
           model: "test",
           usage: %Usage{input_tokens: 100, output_tokens: 50}
         }},
        {:content_block_start, 0, %{type: "text", text: ""}},
        {:content_block_delta, 0, %{type: "text_delta", text: "Integration test response."}},
        {:content_block_stop, 0},
        {:message_delta, %{"stop_reason" => "end_turn"},
         %Usage{input_tokens: 100, output_tokens: 50}},
        :message_stop
      ]

      {:ok, events}
    end
  end

  test "full conversation loop: send message, get response, check session state" do
    {:ok, session} = Session.start_link(id: "int-1")

    handler = fn event ->
      send(self(), {:event, event})
      :ok
    end

    {:ok, result} =
      Conversation.run(
        session: session,
        model: "test",
        user_input: "Hello from integration",
        event_handler: handler,
        provider_module: SimpleProvider,
        project_root: System.tmp_dir!(),
        permission_mode: :allow
      )

    assert result.text == "Integration test response."
    assert result.iterations == 1

    messages = Session.get_messages(session)
    assert length(messages) == 2
    assert hd(messages).role == :user
    assert List.last(messages).role == :assistant

    usage = Session.get_usage(session)
    assert usage.input_tokens == 100
    assert usage.output_tokens == 50
  end

  test "command system integration: parse, lookup, execute" do
    {:ok, session} = Session.start_link(id: "int-cmd")

    assert {:command, "status", []} = Parser.parse("/status")
    {:ok, spec} = Registry.get("status")

    {:ok, output} =
      spec.handler.execute([], %{
        session: session,
        model: "sonnet",
        permission_mode: :prompt
      })

    assert output =~ "Model: sonnet"
    assert output =~ "Messages: 0"
  end

  test "clear command resets session" do
    {:ok, session} = Session.start_link(id: "int-clear")

    Session.add_message(session, %{role: :user, blocks: [{:text, "msg1"}], usage: nil})
    Session.add_message(session, %{role: :assistant, blocks: [{:text, "reply1"}], usage: nil})
    assert length(Session.get_messages(session)) == 2

    {:ok, spec} = Registry.get("clear")
    {:ok, output} = spec.handler.execute([], %{session: session})
    assert output == "Session cleared."
    assert length(Session.get_messages(session)) == 0
  end

  test "compact reduces message count" do
    {:ok, session} = Session.start_link(id: "int-compact")

    for i <- 1..10 do
      Session.add_message(session, %{
        role: :user,
        blocks: [{:text, "Message #{i}"}],
        usage: nil
      })

      Session.add_message(session, %{
        role: :assistant,
        blocks: [{:text, "Reply #{i}"}],
        usage: nil
      })
    end

    assert length(Session.get_messages(session)) == 20
    {:ok, removed} = Compact.compact(session)
    assert removed > 0
    assert length(Session.get_messages(session)) < 20
  end

  test "event handler receives events in order" do
    {:ok, session} = Session.start_link(id: "int-events")

    events = :ets.new(:int_events, [:ordered_set, :public])

    handler = fn event ->
      :ets.insert(events, {System.monotonic_time(), event})
      :ok
    end

    Conversation.run(
      session: session,
      model: "test",
      user_input: "test",
      event_handler: handler,
      provider_module: SimpleProvider,
      project_root: System.tmp_dir!(),
      permission_mode: :allow
    )

    recorded =
      :ets.tab2list(events)
      |> Enum.sort_by(fn {t, _} -> t end)
      |> Enum.map(fn {_, e} -> e end)

    assert Enum.any?(recorded, &match?({:text_delta, _}, &1))
    assert List.last(recorded) |> elem(0) == :turn_complete
    :ets.delete(events)
  end

  test "renderer produces ANSI output" do
    output = Renderer.render_markdown("# Hello\n**bold** `code`")
    rendered = IO.iodata_to_binary(output)
    assert rendered =~ "Hello"
    assert rendered =~ "bold"
    assert rendered =~ "code"
  end

  test "session persistence round-trip" do
    dir = Path.join(System.tmp_dir!(), "viber-int-persist")
    File.mkdir_p!(dir)
    path = Path.join(dir, "session.json")

    {:ok, session} = Session.start_link(id: "int-persist", storage_path: path)

    Session.add_message(session, %{role: :user, blocks: [{:text, "persist me"}], usage: nil})

    Session.add_message(session, %{
      role: :assistant,
      blocks: [{:text, "persisted"}],
      usage: %Viber.Runtime.Usage{input_tokens: 10, output_tokens: 5, turns: 1}
    })

    {:ok, ^path} = Session.save(session)
    {:ok, loaded} = Session.load(path)
    assert length(loaded.messages) == 2
    assert hd(loaded.messages).role == :user

    File.rm_rf!(dir)
  end
end
