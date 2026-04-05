defmodule Viber.API.SSEParserTest do
  use ExUnit.Case, async: true

  alias Viber.API.SSEParser

  test "parses single frame" do
    frame =
      "event: content_block_start\n" <>
        "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"Hi\"}}\n\n"

    {:ok, _parser, events} = SSEParser.push(SSEParser.new(), frame)
    assert [{:content_block_start, 0, %{type: "text", text: "Hi"}}] = events
  end

  test "parses chunked stream" do
    first =
      "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel"

    second = "lo\"}}\n\n"

    {:ok, parser, events} = SSEParser.push(SSEParser.new(), first)
    assert events == []

    {:ok, _parser, events} = SSEParser.push(parser, second)
    assert [{:content_block_delta, 0, %{type: "text_delta", text: "Hello"}}] = events
  end

  test "ignores ping and done" do
    payload =
      ": keepalive\n" <>
        "event: ping\n" <>
        "data: {\"type\":\"ping\"}\n\n" <>
        "event: message_delta\n" <>
        "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\",\"stop_sequence\":null},\"usage\":{\"input_tokens\":1,\"output_tokens\":2}}\n\n" <>
        "event: message_stop\n" <>
        "data: {\"type\":\"message_stop\"}\n\n" <>
        "data: [DONE]\n\n"

    {:ok, _parser, events} = SSEParser.push(SSEParser.new(), payload)

    assert [
             {:message_delta, %{"stop_reason" => "tool_use", "stop_sequence" => nil},
              %Viber.API.Usage{input_tokens: 1, output_tokens: 2}},
             :message_stop
           ] = events
  end

  test "ignores data-less event frames" do
    frame = "event: ping\n\n"
    {:ok, _parser, events} = SSEParser.push(SSEParser.new(), frame)
    assert events == []
  end

  test "parses split JSON across data lines" do
    frame =
      "event: content_block_delta\n" <>
        "data: {\"type\":\"content_block_delta\",\"index\":0,\n" <>
        "data: \"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n"

    {:ok, _parser, events} = SSEParser.push(SSEParser.new(), frame)
    assert [{:content_block_delta, 0, %{type: "text_delta", text: "Hello"}}] = events
  end

  test "parses thinking content block start" do
    frame =
      "event: content_block_start\n" <>
        "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\",\"signature\":null}}\n\n"

    {:ok, _parser, events} = SSEParser.push(SSEParser.new(), frame)
    assert [{:content_block_start, 0, %{type: "thinking", thinking: "", signature: nil}}] = events
  end
end
