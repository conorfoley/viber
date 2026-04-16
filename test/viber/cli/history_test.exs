defmodule Viber.CLI.HistoryTest do
  use ExUnit.Case, async: true

  alias Viber.CLI.History

  describe "new/1" do
    test "creates empty history with defaults" do
      h = History.new()
      assert h.entries == []
      assert h.position == -1
      assert h.max == 500
      assert h.persist_path == nil
    end

    test "accepts custom max" do
      h = History.new(max: 10)
      assert h.max == 10
    end

    test "persist: false keeps in-memory only" do
      h = History.new(persist: false)
      assert h.persist_path == nil
    end

    test "persist: true sets default path" do
      h = History.new(persist: true)
      assert h.persist_path == Path.expand("~/.viber_history")
    end

    test "persist: custom path sets that path" do
      h = History.new(persist: "/tmp/test_viber_history")
      assert h.persist_path == "/tmp/test_viber_history"
    end
  end

  describe "push/2" do
    test "adds entry and resets position" do
      h = History.new() |> History.push("hello")
      assert h.entries == ["hello"]
      assert h.position == -1
    end

    test "most recent entry is first" do
      h =
        History.new()
        |> History.push("first")
        |> History.push("second")

      assert h.entries == ["second", "first"]
    end

    test "blank lines are not added" do
      h = History.new() |> History.push("") |> History.push("   ")
      assert h.entries == []
    end

    test "whitespace-only input is not added" do
      h = History.new() |> History.push("\t\n")
      assert h.entries == []
    end

    test "duplicate of most recent entry is suppressed" do
      h =
        History.new()
        |> History.push("hello")
        |> History.push("hello")

      assert h.entries == ["hello"]
    end

    test "same entry after a different one is allowed" do
      h =
        History.new()
        |> History.push("hello")
        |> History.push("world")
        |> History.push("hello")

      assert h.entries == ["hello", "world", "hello"]
    end

    test "duplicate push resets navigation position" do
      h = History.new() |> History.push("hello")
      {_, h} = History.previous(h)
      assert h.position == 0

      h = History.push(h, "hello")
      assert h.position == -1
    end

    test "trims whitespace before storing" do
      h = History.new() |> History.push("  hello  ")
      assert h.entries == ["hello"]
    end

    test "enforces max size" do
      h = History.new(max: 3)

      h =
        Enum.reduce(["a", "b", "c", "d"], h, fn entry, acc ->
          History.push(acc, entry)
        end)

      assert length(h.entries) == 3
      assert h.entries == ["d", "c", "b"]
    end
  end

  describe "previous/1 (Up arrow)" do
    test "returns nil on empty history" do
      h = History.new()
      assert {nil, _} = History.previous(h)
    end

    test "returns most recent entry on first Up" do
      h = History.new() |> History.push("first") |> History.push("second")
      {entry, h} = History.previous(h)
      assert entry == "second"
      assert h.position == 0
    end

    test "navigates to older entries on repeated Up" do
      h =
        History.new()
        |> History.push("first")
        |> History.push("second")
        |> History.push("third")

      {entry1, h} = History.previous(h)
      assert entry1 == "third"

      {entry2, h} = History.previous(h)
      assert entry2 == "second"

      {entry3, _h} = History.previous(h)
      assert entry3 == "first"
    end

    test "stays at oldest entry when pressing Up at boundary" do
      h = History.new() |> History.push("only")
      {_, h} = History.previous(h)

      {entry, h2} = History.previous(h)
      assert entry == "only"
      assert h2.position == h.position
    end
  end

  describe "next/1 (Down arrow)" do
    test "returns nil when not navigating" do
      h = History.new() |> History.push("hello")
      assert {nil, _} = History.next(h)
    end

    test "moves forward through history" do
      h =
        History.new()
        |> History.push("first")
        |> History.push("second")
        |> History.push("third")

      {_, h} = History.previous(h)
      {_, h} = History.previous(h)
      {_, h} = History.previous(h)

      {entry1, h} = History.next(h)
      assert entry1 == "second"

      {entry2, h} = History.next(h)
      assert entry2 == "third"

      {entry3, h} = History.next(h)
      assert entry3 == nil
      assert h.position == -1
    end

    test "returns nil and resets position after most recent entry" do
      h = History.new() |> History.push("hello")
      {_, h} = History.previous(h)

      {nil, h} = History.next(h)
      assert h.position == -1
    end
  end

  describe "push/navigate cycle" do
    test "full Up/Down cycle" do
      h =
        History.new()
        |> History.push("cmd1")
        |> History.push("cmd2")
        |> History.push("cmd3")

      {e1, h} = History.previous(h)
      assert e1 == "cmd3"

      {e2, h} = History.previous(h)
      assert e2 == "cmd2"

      {e3, h} = History.previous(h)
      assert e3 == "cmd1"

      {e4, h} = History.next(h)
      assert e4 == "cmd2"

      {e5, h} = History.next(h)
      assert e5 == "cmd3"

      {e6, h} = History.next(h)
      assert e6 == nil
      assert h.position == -1
    end

    test "pushing new entry resets navigation" do
      h = History.new() |> History.push("first") |> History.push("second")
      {_, h} = History.previous(h)
      assert h.position == 0

      h = History.push(h, "third")
      assert h.position == -1
      assert hd(h.entries) == "third"
    end
  end

  describe "to_list/1" do
    test "returns empty list for new history" do
      assert History.to_list(History.new()) == []
    end

    test "returns entries most recent first" do
      h =
        History.new()
        |> History.push("a")
        |> History.push("b")
        |> History.push("c")

      assert History.to_list(h) == ["c", "b", "a"]
    end
  end

  describe "file persistence" do
    @tag :tmp_dir
    test "persists entries to file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "history")
      h = History.new(persist: path) |> History.push("hello") |> History.push("world")

      assert {:ok, content} = File.read(path)
      assert content == "hello\nworld\n"

      _ = h
    end

    @tag :tmp_dir
    test "loads entries from existing file on new/1", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "history")
      File.write!(path, "first\nsecond\nthird\n")

      h = History.new(persist: path)
      assert History.to_list(h) == ["third", "second", "first"]
    end

    @tag :tmp_dir
    test "handles missing file gracefully on new/1", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "nonexistent_history")
      h = History.new(persist: path)
      assert History.to_list(h) == []
    end
  end
end
