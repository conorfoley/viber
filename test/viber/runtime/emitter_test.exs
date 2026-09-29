defmodule Viber.Runtime.EmitterTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.{Emitter, Event}

  defp collecting_sink do
    parent = self()
    fn event -> send(parent, {:event, event}) end
  end

  test "stamps run_id, session_id and a monotonic seq" do
    emitter = Emitter.new(collecting_sink(), run_id: "run_1", session_id: "s1")

    Emitter.emit(emitter, Event.new(:text_delta, %{text: "a"}))
    Emitter.emit(emitter, Event.new(:text_delta, %{text: "b"}, seq: 99))

    assert_receive {:event, %Event{run_id: "run_1", session_id: "s1", seq: 1}}
    assert_receive {:event, %Event{run_id: "run_1", seq: 2}}
  end

  test "keeps the run_id and session_id of forwarded events" do
    emitter = Emitter.new(collecting_sink(), run_id: "parent", session_id: "s1")
    Emitter.emit(emitter, Event.new(:tool_result, %{}, run_id: "child", session_id: "s2"))

    assert_receive {:event, %Event{run_id: "child", session_id: "s2", seq: 1}}
  end

  test "seq is unique across concurrent emitters" do
    parent = self()
    emitter = Emitter.new(fn e -> send(parent, {:seq, e.seq}) end)

    1..50
    |> Task.async_stream(fn _ -> Emitter.emit(emitter, Event.new(:info, %{message: "x"})) end)
    |> Stream.run()

    seqs =
      for _ <- 1..50 do
        receive do
          {:seq, seq} -> seq
        after
          1_000 -> flunk("missing event")
        end
      end

    assert Enum.sort(seqs) == Enum.to_list(1..50)
  end

  test "a failing sink is reported to the owner and does not raise" do
    emitter = Emitter.new(fn _ -> raise "boom" end, run_id: "run_x")

    assert :ok = Emitter.emit(emitter, Event.new(:info, %{message: "x"}))

    assert_receive {:viber_event_sink_failed, "run_x",
                    %{seq: 1, type: :info, reason: %RuntimeError{message: "boom"}}}
  end

  test "generated run ids are prefixed and distinct" do
    a = Emitter.generate_run_id()
    assert "run_" <> _ = a
    refute a == Emitter.generate_run_id()
  end
end
