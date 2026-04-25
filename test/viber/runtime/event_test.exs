defmodule Viber.Runtime.EventTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.{Event, Usage}
  alias Viber.Runtime.Event.Legacy

  describe "to_map/1" do
    test "produces versioned wire payload with stringified keys" do
      event =
        Event.new(:text_delta, %{text: "hello"},
          session_id: "s1",
          seq: 3,
          timestamp: ~U[2026-04-16 21:00:00Z]
        )

      assert %{
               "v" => 1,
               "type" => "text_delta",
               "payload" => %{"text" => "hello"},
               "session_id" => "s1",
               "seq" => 3,
               "timestamp" => "2026-04-16T21:00:00Z"
             } = Event.to_map(event)
    end

    test "flattens Usage structs in payload" do
      usage = %Usage{input_tokens: 10, output_tokens: 20, turns: 1}
      event = Event.new(:turn_complete, %{usage: usage})

      map = Event.to_map(event)

      assert map["payload"]["usage"]["input_tokens"] == 10
      assert map["payload"]["usage"]["output_tokens"] == 20
      assert map["payload"]["usage"]["total_tokens"] == 30
    end

    test "is JSON-encodable" do
      event =
        Event.new(:tool_result, %{
          name: "bash",
          id: "t1",
          output: "ok",
          is_error: false
        })

      json = Jason.encode!(Event.to_map(event))
      assert is_binary(json)
      assert Jason.decode!(json)["type"] == "tool_result"
    end
  end

  describe "from_map/1" do
    test "round-trips a basic text_delta" do
      original = Event.new(:text_delta, %{text: "hi"}, session_id: "s1", seq: 1)
      {:ok, decoded} = original |> Event.to_map() |> Event.from_map()

      assert decoded.type == :text_delta
      assert decoded.payload == %{text: "hi"}
      assert decoded.session_id == "s1"
      assert decoded.seq == 1
    end

    test "rejects unknown event types" do
      assert {:error, :unknown_event_type} =
               Event.from_map(%{"type" => "bogus", "payload" => %{}})
    end

    test "rejects malformed input" do
      assert {:error, :invalid_event} = Event.from_map(%{"no" => "type"})
    end
  end

  describe "Legacy.to_tuple/1 and from_tuple/1" do
    test "text_delta round-trip" do
      tup = {:text_delta, "hi"}
      assert ^tup = tup |> Legacy.from_tuple() |> Legacy.to_tuple()
    end

    test "tool_result round-trip" do
      tup = {:tool_result, "bash", "out", false}
      assert ^tup = tup |> Legacy.from_tuple() |> Legacy.to_tuple()
    end

    test "turn_complete round-trip preserves Usage" do
      usage = %Usage{input_tokens: 5, output_tokens: 7, turns: 1}
      tup = {:turn_complete, usage}
      assert {:turn_complete, ^usage} = tup |> Legacy.from_tuple() |> Legacy.to_tuple()
    end

    test "interrupted round-trip" do
      tup = {:interrupted, "Interrupted"}
      assert ^tup = tup |> Legacy.from_tuple() |> Legacy.to_tuple()
    end
  end
end
