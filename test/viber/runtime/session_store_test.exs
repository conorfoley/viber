defmodule Viber.Runtime.SessionStoreTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.{SessionStore, Usage}

  describe "available?/0" do
    test "returns boolean based on repo process" do
      result = SessionStore.available?()
      assert is_boolean(result)
    end
  end

  describe "persist/4 without repo" do
    @tag :requires_no_repo
    test "returns {:error, :repo_unavailable} when repo is down" do
      messages = [%{role: :user, blocks: [{:text, "hi"}], usage: nil}]
      assert {:error, :repo_unavailable} = SessionStore.persist("test-id", messages, %Usage{})
    end
  end

  describe "load_session/1 without repo" do
    @tag :requires_no_repo
    test "returns {:error, :repo_unavailable} when repo is down" do
      assert {:error, :repo_unavailable} = SessionStore.load_session("nonexistent")
    end
  end

  describe "list_recent/1 without repo" do
    @tag :requires_no_repo
    test "returns empty list when repo is down" do
      assert [] = SessionStore.list_recent(10)
    end
  end

  describe "delete_session/1 without repo" do
    test "returns :ok even when repo is down" do
      assert :ok = SessionStore.delete_session("nonexistent")
    end
  end

  describe "encode/decode round-trip" do
    test "message with text block" do
      msg = %{role: :user, blocks: [{:text, "hello"}], usage: nil}
      encoded = encode_message(msg)

      assert encoded["role"] == "user"
      assert [%{"type" => "text", "text" => "hello"}] = encoded["blocks"]
      refute Map.has_key?(encoded, "usage")

      decoded = decode_message(encoded)
      assert decoded.role == :user
      assert [{:text, "hello"}] = decoded.blocks
      assert decoded.usage == nil
    end

    test "message with tool_use block" do
      msg = %{
        role: :assistant,
        blocks: [{:text, "thinking"}, {:tool_use, "t1", "bash", %{"command" => "ls"}}],
        usage: %Usage{input_tokens: 10, output_tokens: 5, turns: 1}
      }

      encoded = encode_message(msg)
      assert encoded["role"] == "assistant"
      assert length(encoded["blocks"]) == 2
      assert encoded["usage"]["input_tokens"] == 10

      decoded = decode_message(encoded)
      assert decoded.role == :assistant
      assert {:text, "thinking"} = Enum.at(decoded.blocks, 0)
      assert {:tool_use, "t1", "bash", %{"command" => "ls"}} = Enum.at(decoded.blocks, 1)
      assert decoded.usage.input_tokens == 10
    end

    test "message with tool_result block" do
      msg = %{
        role: :tool,
        blocks: [{:tool_result, "t1", "bash", "output here", false}],
        usage: nil
      }

      encoded = encode_message(msg)
      decoded = decode_message(encoded)
      assert decoded.role == :tool
      assert [{:tool_result, "t1", "bash", "output here", false}] = decoded.blocks
    end

    test "usage encode/decode round-trip" do
      usage = %Usage{
        input_tokens: 100,
        output_tokens: 50,
        cache_creation_tokens: 10,
        cache_read_tokens: 5,
        turns: 3
      }

      encoded = encode_usage(usage)
      assert encoded["input_tokens"] == 100
      assert encoded["turns"] == 3

      decoded = decode_usage(encoded)
      assert decoded.input_tokens == 100
      assert decoded.output_tokens == 50
      assert decoded.cache_creation_tokens == 10
      assert decoded.cache_read_tokens == 5
      assert decoded.turns == 3
    end

    test "encode_usage handles nil" do
      assert %{} = encode_usage(nil)
    end

    test "decode_usage handles nil" do
      assert %Usage{input_tokens: 0} = decode_usage(nil)
    end
  end

  defp encode_message(msg) do
    json = %{
      "role" => Atom.to_string(msg.role),
      "blocks" => Enum.map(msg.blocks, &encode_block/1)
    }

    if msg[:usage] do
      Map.put(json, "usage", encode_usage(msg.usage))
    else
      json
    end
  end

  defp encode_block({:text, text}), do: %{"type" => "text", "text" => text}

  defp encode_block({:tool_use, id, name, input}),
    do: %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}

  defp encode_block({:tool_result, tool_use_id, tool_name, output, is_error}),
    do: %{
      "type" => "tool_result",
      "tool_use_id" => tool_use_id,
      "tool_name" => tool_name,
      "output" => output,
      "is_error" => is_error
    }

  defp encode_usage(%Usage{} = u) do
    %{
      "input_tokens" => u.input_tokens,
      "output_tokens" => u.output_tokens,
      "cache_creation_tokens" => u.cache_creation_tokens,
      "cache_read_tokens" => u.cache_read_tokens,
      "turns" => u.turns
    }
  end

  defp encode_usage(_), do: %{}

  defp decode_message(json) do
    role = decode_role(json["role"])
    blocks = Enum.map(json["blocks"] || [], &decode_block/1)
    usage = if json["usage"], do: decode_usage(json["usage"]), else: nil
    %{role: role, blocks: blocks, usage: usage}
  end

  defp decode_role("system"), do: :system
  defp decode_role("user"), do: :user
  defp decode_role("assistant"), do: :assistant
  defp decode_role("tool"), do: :tool

  defp decode_block(%{"type" => "text", "text" => text}), do: {:text, text}

  defp decode_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}),
    do: {:tool_use, id, name, input}

  defp decode_block(%{
         "type" => "tool_result",
         "tool_use_id" => tool_use_id,
         "tool_name" => tool_name,
         "output" => output,
         "is_error" => is_error
       }),
       do: {:tool_result, tool_use_id, tool_name, output, is_error}

  defp decode_usage(json) when is_map(json) do
    %Usage{
      input_tokens: json["input_tokens"] || 0,
      output_tokens: json["output_tokens"] || 0,
      cache_creation_tokens: json["cache_creation_tokens"] || 0,
      cache_read_tokens: json["cache_read_tokens"] || 0,
      turns: json["turns"] || 0
    }
  end

  defp decode_usage(_), do: %Usage{}
end
