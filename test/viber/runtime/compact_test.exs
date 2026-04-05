defmodule Viber.Runtime.CompactTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.{Compact, Session}

  test "should_compact? returns false for short conversations" do
    {:ok, session} = Session.start_link(id: "compact-1")
    Session.add_message(session, %{role: :user, blocks: [{:text, "hello"}], usage: nil})
    refute Compact.should_compact?(session)
  end

  test "should_compact? returns true for long conversations" do
    {:ok, session} = Session.start_link(id: "compact-2")
    long_text = String.duplicate("x", 500_000)

    for _ <- 1..5 do
      Session.add_message(session, %{role: :user, blocks: [{:text, long_text}], usage: nil})
    end

    assert Compact.should_compact?(session)
  end

  test "compact reduces message count" do
    {:ok, session} = Session.start_link(id: "compact-3")

    for i <- 1..10 do
      Session.add_message(session, %{role: :user, blocks: [{:text, "message #{i}"}], usage: nil})
    end

    assert {:ok, removed} = Compact.compact(session, preserve_recent: 4)
    assert removed == 6
    messages = Session.get_messages(session)
    assert length(messages) == 5
  end

  test "estimate_tokens heuristic" do
    messages = [
      %{role: :user, blocks: [{:text, String.duplicate("a", 400)}], usage: nil}
    ]

    assert Compact.estimate_tokens(messages) == 100
  end

  test "compact with few messages is a no-op" do
    {:ok, session} = Session.start_link(id: "compact-4")
    Session.add_message(session, %{role: :user, blocks: [{:text, "hello"}], usage: nil})
    assert {:ok, 0} = Compact.compact(session)
  end
end
