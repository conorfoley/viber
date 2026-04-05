defmodule Viber.Runtime.SessionTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.{Session, Usage}

  describe "start_link and basic operations" do
    test "creates empty session" do
      {:ok, pid} = Session.start_link(id: "test-1")
      assert Session.get_messages(pid) == []
      assert %Usage{input_tokens: 0, output_tokens: 0} = Session.get_usage(pid)
    end

    test "add_message and get_messages round-trip" do
      {:ok, pid} = Session.start_link(id: "test-2")
      msg = %{role: :user, blocks: [{:text, "hello"}], usage: nil}
      :ok = Session.add_message(pid, msg)
      assert [^msg] = Session.get_messages(pid)
    end

    test "accumulates usage across messages" do
      {:ok, pid} = Session.start_link(id: "test-3")

      msg1 = %{
        role: :assistant,
        blocks: [{:text, "hi"}],
        usage: %Usage{
          input_tokens: 10,
          output_tokens: 4,
          cache_creation_tokens: 2,
          cache_read_tokens: 1,
          turns: 1
        }
      }

      msg2 = %{
        role: :assistant,
        blocks: [{:text, "there"}],
        usage: %Usage{
          input_tokens: 20,
          output_tokens: 6,
          cache_creation_tokens: 3,
          cache_read_tokens: 2,
          turns: 1
        }
      }

      :ok = Session.add_message(pid, msg1)
      :ok = Session.add_message(pid, msg2)

      usage = Session.get_usage(pid)
      assert usage.input_tokens == 30
      assert usage.output_tokens == 10
      assert usage.cache_creation_tokens == 5
      assert usage.cache_read_tokens == 3
      assert usage.turns == 2
    end

    test "clear resets history and usage" do
      {:ok, pid} = Session.start_link(id: "test-4")
      msg = %{role: :user, blocks: [{:text, "hello"}], usage: nil}
      :ok = Session.add_message(pid, msg)
      :ok = Session.clear(pid)
      assert Session.get_messages(pid) == []
      assert %Usage{input_tokens: 0} = Session.get_usage(pid)
    end

    test "replace_messages for compaction" do
      {:ok, pid} = Session.start_link(id: "test-5")

      original = %{
        role: :assistant,
        blocks: [{:text, "verbose"}],
        usage: %Usage{input_tokens: 100, output_tokens: 50, turns: 1}
      }

      :ok = Session.add_message(pid, original)

      compacted = %{
        role: :assistant,
        blocks: [{:text, "compact"}],
        usage: %Usage{input_tokens: 10, output_tokens: 5, turns: 1}
      }

      :ok = Session.replace_messages(pid, [compacted])
      assert [^compacted] = Session.get_messages(pid)
      usage = Session.get_usage(pid)
      assert usage.input_tokens == 10
      assert usage.output_tokens == 5
    end
  end

  describe "persistence" do
    @tag :tmp_dir
    test "save and load round-trip", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "session.json")
      {:ok, pid} = Session.start_link(id: "persist-1", storage_path: path)

      :ok =
        Session.add_message(pid, %{
          role: :user,
          blocks: [{:text, "hello"}],
          usage: nil
        })

      :ok =
        Session.add_message(pid, %{
          role: :assistant,
          blocks: [
            {:text, "thinking"},
            {:tool_use, "tool-1", "bash", "echo hi"}
          ],
          usage: %Usage{
            input_tokens: 10,
            output_tokens: 4,
            cache_creation_tokens: 1,
            cache_read_tokens: 2,
            turns: 1
          }
        })

      :ok =
        Session.add_message(pid, %{
          role: :tool,
          blocks: [{:tool_result, "tool-1", "bash", "hi", false}],
          usage: nil
        })

      assert {:ok, ^path} = Session.save(pid)
      assert File.exists?(path)

      {:ok, restored} = Session.load(path)
      assert length(restored.messages) == 3

      [user_msg, assistant_msg, tool_msg] = restored.messages
      assert user_msg.role == :user
      assert user_msg.blocks == [{:text, "hello"}]

      assert assistant_msg.role == :assistant

      assert assistant_msg.blocks == [
               {:text, "thinking"},
               {:tool_use, "tool-1", "bash", "echo hi"}
             ]

      assert assistant_msg.usage.input_tokens == 10
      assert assistant_msg.usage.output_tokens == 4

      assert tool_msg.role == :tool
      assert [{:tool_result, "tool-1", "bash", "hi", false}] = tool_msg.blocks

      assert Usage.total_tokens(restored.cumulative_usage) == 17
    end

    test "save without storage_path returns error" do
      {:ok, pid} = Session.start_link(id: "no-path")
      assert {:error, :no_storage_path} = Session.save(pid)
    end
  end
end
