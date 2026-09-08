defmodule Viber.Gateway.MessageTest do
  use ExUnit.Case, async: true

  alias Viber.Gateway.Message

  test "builds a message with defaults for optional fields" do
    msg = %Message{
      id: "m1",
      adapter_id: :discord,
      channel_id: "c1",
      user_id: "u1",
      text: "hello"
    }

    assert msg.metadata == %{}
    assert msg.timestamp == nil
  end

  test "accepts explicit metadata and timestamp" do
    now = DateTime.utc_now()

    msg = %Message{
      id: "m2",
      adapter_id: :discord,
      channel_id: "c1",
      user_id: "u1",
      text: "hi",
      metadata: %{"interaction_token" => "abc"},
      timestamp: now
    }

    assert msg.metadata == %{"interaction_token" => "abc"}
    assert msg.timestamp == now
  end

  test "raises when a required key is missing" do
    assert_raise ArgumentError, fn ->
      struct!(Message, id: "m3", adapter_id: :discord, channel_id: "c1", user_id: "u1")
    end
  end
end
