defmodule Viber.Tools.Builtins.FormatterTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.Formatter

  describe "path mode — write" do
    @tag :tmp_dir
    test "formats an unformatted file and returns confirmation", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "sample.ex")
      File.write!(path, "x=1\n")
      assert {:ok, result} = Formatter.execute(%{"path" => path})
      assert result =~ "Formatted:"
      assert result =~ path
      assert File.read!(path) == "x = 1\n"
    end

    @tag :tmp_dir
    test "succeeds when file is already formatted", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "already.ex")
      File.write!(path, "x = 1\n")
      assert {:ok, result} = Formatter.execute(%{"path" => path})
      assert result =~ "Formatted:"
    end
  end

  describe "path mode — check_only" do
    @tag :tmp_dir
    test "returns 'Already formatted' when file is correctly formatted", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "ok.ex")
      File.write!(path, "x = 1\n")
      assert {:ok, result} = Formatter.execute(%{"path" => path, "check_only" => true})
      assert result =~ "Already formatted:"
      assert result =~ path
    end

    @tag :tmp_dir
    test "returns 'Not formatted' when file needs formatting", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "bad.ex")
      File.write!(path, "x=1\n")
      assert {:ok, result} = Formatter.execute(%{"path" => path, "check_only" => true})
      assert result =~ "Not formatted:"
      assert result =~ path
      assert File.read!(path) == "x=1\n"
    end
  end

  describe "content mode — write" do
    test "returns formatted Elixir code" do
      assert {:ok, result} = Formatter.execute(%{"content" => "x=1\n"})
      assert result == "x = 1\n"
    end

    test "returns already-formatted code unchanged" do
      assert {:ok, result} = Formatter.execute(%{"content" => "x = 1\n"})
      assert result == "x = 1\n"
    end
  end

  describe "content mode — check_only" do
    test "returns 'Already formatted.' for well-formatted content" do
      assert {:ok, result} = Formatter.execute(%{"content" => "x = 1\n", "check_only" => true})
      assert result == "Already formatted."
    end

    test "returns 'Not formatted.' for content needing formatting" do
      assert {:ok, result} = Formatter.execute(%{"content" => "x=1\n", "check_only" => true})
      assert result == "Not formatted."
    end
  end

  describe "validation" do
    test "returns error when both path and content are given" do
      assert {:error, msg} =
               Formatter.execute(%{"path" => "foo.ex", "content" => "x = 1\n"})

      assert msg =~ "not both"
    end

    test "returns error when neither path nor content is given" do
      assert {:error, msg} = Formatter.execute(%{})
      assert msg =~ "path"
      assert msg =~ "content"
    end

    test "returns error when neither path nor content given even with check_only" do
      assert {:error, _msg} = Formatter.execute(%{"check_only" => true})
    end
  end
end
