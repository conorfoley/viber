defmodule Viber.Tools.Builtins.FileOpsTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.FileOps

  @tag :tmp_dir
  test "read existing file", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "test.txt")
    File.write!(path, "line one\nline two\nline three")

    assert {:ok, result} = FileOps.read(%{"path" => path})
    assert result =~ "line one"
    assert result =~ "line two"
    assert result =~ "line three"
  end

  @tag :tmp_dir
  test "read with offset and limit", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "test2.txt")
    File.write!(path, "a\nb\nc\nd\ne")

    assert {:ok, result} = FileOps.read(%{"path" => path, "offset" => 1, "limit" => 2})
    assert result =~ "b"
    assert result =~ "c"
    refute result =~ "\ta\n"
  end

  test "read missing file returns error" do
    assert {:error, msg} = FileOps.read(%{"path" => "/nonexistent/file.txt"})
    assert msg =~ "Failed to read"
  end

  @tag :tmp_dir
  test "write creates file with parent dirs", %{tmp_dir: tmp_dir} do
    path = Path.join([tmp_dir, "sub", "dir", "file.txt"])
    assert {:ok, result} = FileOps.write(%{"path" => path, "content" => "hello"})
    assert result =~ "5 bytes"
    assert File.read!(path) == "hello"
  end

  @tag :tmp_dir
  test "edit replaces unique match", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "edit.txt")
    File.write!(path, "foo bar baz")

    assert {:ok, result} =
             FileOps.edit(%{"path" => path, "old_string" => "bar", "new_string" => "qux"})

    assert result =~ "1 occurrence"
    assert File.read!(path) == "foo qux baz"
  end

  @tag :tmp_dir
  test "edit fails on non-unique match without replace_all", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "dup.txt")
    File.write!(path, "aaa bbb aaa")

    assert {:error, msg} =
             FileOps.edit(%{"path" => path, "old_string" => "aaa", "new_string" => "ccc"})

    assert msg =~ "2 times"
  end

  @tag :tmp_dir
  test "edit with replace_all replaces all matches", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "all.txt")
    File.write!(path, "aaa bbb aaa")

    assert {:ok, _} =
             FileOps.edit(%{
               "path" => path,
               "old_string" => "aaa",
               "new_string" => "ccc",
               "replace_all" => true
             })

    assert File.read!(path) == "ccc bbb ccc"
  end

  test "edit rejects same old_string and new_string" do
    assert {:error, msg} =
             FileOps.edit(%{"path" => "/tmp/x", "old_string" => "a", "new_string" => "a"})

    assert msg =~ "must differ"
  end
end
