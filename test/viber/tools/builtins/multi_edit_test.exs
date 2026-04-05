defmodule Viber.Tools.Builtins.MultiEditTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.MultiEdit

  @tag :tmp_dir
  test "applies multiple edits to a single file", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "single.txt")
    File.write!(path, "aaa bbb ccc")

    assert {:ok, msg} =
             MultiEdit.execute(%{
               "edits" => [
                 %{"path" => path, "old_string" => "aaa", "new_string" => "xxx"},
                 %{"path" => path, "old_string" => "ccc", "new_string" => "zzz"}
               ]
             })

    assert msg =~ "1 file"
    assert File.read!(path) == "xxx bbb zzz"
  end

  @tag :tmp_dir
  test "applies edits across multiple files", %{tmp_dir: tmp_dir} do
    path1 = Path.join(tmp_dir, "file1.txt")
    path2 = Path.join(tmp_dir, "file2.txt")
    File.write!(path1, "hello world")
    File.write!(path2, "foo bar")

    assert {:ok, msg} =
             MultiEdit.execute(%{
               "edits" => [
                 %{"path" => path1, "old_string" => "hello", "new_string" => "hi"},
                 %{"path" => path2, "old_string" => "foo", "new_string" => "baz"}
               ]
             })

    assert msg =~ "2 files"
    assert File.read!(path1) == "hi world"
    assert File.read!(path2) == "baz bar"
  end

  @tag :tmp_dir
  test "aborts all edits when one fails validation", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "abort.txt")
    File.write!(path, "aaa bbb ccc")

    assert {:error, msg} =
             MultiEdit.execute(%{
               "edits" => [
                 %{"path" => path, "old_string" => "aaa", "new_string" => "xxx"},
                 %{"path" => path, "old_string" => "MISSING", "new_string" => "yyy"}
               ]
             })

    assert msg =~ "Edit 1"
    assert msg =~ "not found"
    assert File.read!(path) == "aaa bbb ccc"
  end

  @tag :tmp_dir
  test "rejects ambiguous match without replace_all", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "dup.txt")
    File.write!(path, "aaa bbb aaa")

    assert {:error, msg} =
             MultiEdit.execute(%{
               "edits" => [
                 %{"path" => path, "old_string" => "aaa", "new_string" => "xxx"}
               ]
             })

    assert msg =~ "2 times"
  end

  @tag :tmp_dir
  test "replace_all replaces all occurrences", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "all.txt")
    File.write!(path, "aaa bbb aaa")

    assert {:ok, _} =
             MultiEdit.execute(%{
               "edits" => [
                 %{
                   "path" => path,
                   "old_string" => "aaa",
                   "new_string" => "xxx",
                   "replace_all" => true
                 }
               ]
             })

    assert File.read!(path) == "xxx bbb xxx"
  end

  test "rejects empty edits array" do
    assert {:error, msg} = MultiEdit.execute(%{"edits" => []})
    assert msg =~ "must not be empty"
  end

  test "rejects missing edits key" do
    assert {:error, msg} = MultiEdit.execute(%{})
    assert msg =~ "Missing required parameter"
  end

  test "rejects edit with same old_string and new_string" do
    assert {:error, msg} =
             MultiEdit.execute(%{
               "edits" => [
                 %{"path" => "/tmp/x", "old_string" => "a", "new_string" => "a"}
               ]
             })

    assert msg =~ "must differ"
  end

  test "rejects edit missing required fields" do
    assert {:error, msg} =
             MultiEdit.execute(%{
               "edits" => [%{"path" => "/tmp/x", "old_string" => "a"}]
             })

    assert msg =~ "missing required field"
  end

  @tag :tmp_dir
  test "sequential edits on the same file see previous results", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "chain.txt")
    File.write!(path, "alpha beta gamma")

    assert {:ok, _} =
             MultiEdit.execute(%{
               "edits" => [
                 %{"path" => path, "old_string" => "alpha", "new_string" => "ALPHA"},
                 %{"path" => path, "old_string" => "ALPHA beta", "new_string" => "DONE"}
               ]
             })

    assert File.read!(path) == "DONE gamma"
  end

  @tag :tmp_dir
  test "handles file read error", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "nonexistent.txt")

    assert {:error, msg} =
             MultiEdit.execute(%{
               "edits" => [
                 %{"path" => path, "old_string" => "a", "new_string" => "b"}
               ]
             })

    assert msg =~ "Failed to read"
  end
end
