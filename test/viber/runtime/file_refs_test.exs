defmodule Viber.Runtime.FileRefsTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.FileRefs

  setup do
    tmp = System.tmp_dir!() |> Path.join("file_refs_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "resolve_pattern/2" do
    test "literal path that exists returns ok tuple", %{tmp: tmp} do
      path = Path.join(tmp, "hello.txt")
      File.write!(path, "hello world")

      assert [{:ok, ^path, "hello world"}] = FileRefs.resolve_pattern(path, tmp)
    end

    test "literal path that is missing returns error tuple", %{tmp: tmp} do
      pattern = Path.join(tmp, "missing.txt")
      assert [{:error, ^pattern, "no files matched"}] = FileRefs.resolve_pattern(pattern, tmp)
    end

    test "relative pattern resolved against base_dir", %{tmp: tmp} do
      path = Path.join(tmp, "rel.txt")
      File.write!(path, "relative")

      assert [{:ok, ^path, "relative"}] = FileRefs.resolve_pattern("rel.txt", tmp)
    end

    test "glob matching zero files returns error", %{tmp: tmp} do
      assert [{:error, _, "no files matched"}] = FileRefs.resolve_pattern("*.nonexistent", tmp)
    end

    test "glob matching one file returns single ok tuple", %{tmp: tmp} do
      path = Path.join(tmp, "a.ex")
      File.write!(path, "content a")

      results = FileRefs.resolve_pattern("*.ex", tmp)
      assert [{:ok, ^path, "content a"}] = results
    end

    test "glob matching multiple files returns multiple ok tuples", %{tmp: tmp} do
      for name <- ~w[a.txt b.txt c.txt] do
        File.write!(Path.join(tmp, name), name)
      end

      results = FileRefs.resolve_pattern("*.txt", tmp)
      assert length(results) == 3
      assert Enum.all?(results, fn {:ok, _, _} -> true end)
    end

    test "glob matching more than 50 files caps at 50 and appends error", %{tmp: tmp} do
      for i <- 1..55 do
        File.write!(
          Path.join(tmp, "f#{String.pad_leading(Integer.to_string(i), 3, "0")}.cap"),
          "x"
        )
      end

      results = FileRefs.resolve_pattern("*.cap", tmp)
      ok_count = Enum.count(results, fn {tag, _, _} -> tag == :ok end)
      error_count = Enum.count(results, fn {tag, _, _} -> tag == :error end)

      assert ok_count == 50
      assert error_count == 1

      {:error, _, reason} = List.last(results)
      assert reason =~ "truncated"
    end

    test "unreadable file returns error tuple", %{tmp: tmp} do
      path = Path.join(tmp, "unreadable.txt")
      File.write!(path, "secret")
      File.chmod!(path, 0o000)

      results = FileRefs.resolve_pattern(path, tmp)

      File.chmod!(path, 0o644)

      assert [{:error, ^path, _reason}] = results
    end
  end

  describe "format_block/2" do
    test "wraps path and content in file markers" do
      result = FileRefs.format_block("/some/path.ex", "defmodule Foo do\nend")
      assert result == "<file: /some/path.ex>\ndefmodule Foo do\nend\n</file>"
    end

    test "handles empty content" do
      result = FileRefs.format_block("/empty.txt", "")
      assert result == "<file: /empty.txt>\n\n</file>"
    end
  end

  describe "format_results/1" do
    test "partitions successes and failures" do
      results = [
        {:ok, "/a.txt", "aaa"},
        {:error, "/b.txt", "no such file"},
        {:ok, "/c.txt", "ccc"}
      ]

      {combined, errors} = FileRefs.format_results(results)

      assert combined =~ "<file: /a.txt>"
      assert combined =~ "<file: /c.txt>"
      refute combined =~ "/b.txt"

      assert length(errors) == 1
      assert hd(errors) =~ "/b.txt"
      assert hd(errors) =~ "no such file"
    end

    test "all successes produces empty error list" do
      results = [{:ok, "/x.txt", "x"}, {:ok, "/y.txt", "y"}]
      {combined, errors} = FileRefs.format_results(results)

      assert combined =~ "<file: /x.txt>"
      assert combined =~ "<file: /y.txt>"
      assert errors == []
    end

    test "all failures produces empty combined string" do
      results = [{:error, "*.gone", "no files matched"}]
      {combined, errors} = FileRefs.format_results(results)

      assert combined == ""
      assert length(errors) == 1
    end

    test "success blocks are joined with double newline" do
      results = [{:ok, "/a.txt", "aaa"}, {:ok, "/b.txt", "bbb"}]
      {combined, _errors} = FileRefs.format_results(results)

      assert combined =~ "\n\n"
    end
  end
end
