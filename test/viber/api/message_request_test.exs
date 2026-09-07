defmodule Viber.API.MessageRequestTest do
  use ExUnit.Case, async: true

  alias Viber.API.{InputMessage, MessageRequest}

  defp base_request do
    %MessageRequest{
      model: "claude-opus-5",
      max_tokens: 1024,
      messages: [InputMessage.user_text("hello")]
    }
  end

  defp encode!(request) do
    request |> Jason.encode!() |> Jason.decode!()
  end

  test "omits thinking and output_config when unset" do
    json = encode!(base_request())

    refute Map.has_key?(json, "thinking")
    refute Map.has_key?(json, "output_config")
  end

  test "encodes thinking when set" do
    request = %{base_request() | thinking: %{type: "adaptive", display: "summarized"}}

    assert encode!(request)["thinking"] == %{
             "type" => "adaptive",
             "display" => "summarized"
           }
  end

  test "encodes output_config effort when set" do
    request = %{base_request() | output_config: %{effort: "low"}}

    assert encode!(request)["output_config"] == %{"effort" => "low"}
  end

  test "encodes system as content block list when caching wraps it" do
    system = [%{type: "text", text: "prompt", cache_control: %{type: "ephemeral"}}]
    request = %{base_request() | system: system}

    assert encode!(request)["system"] == [
             %{
               "type" => "text",
               "text" => "prompt",
               "cache_control" => %{"type" => "ephemeral"}
             }
           ]
  end
end
