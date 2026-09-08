defmodule Viber.Tools.Builtins.GrepTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.Grep

  defp rg_available?, do: not is_nil(System.find_executable("rg"))

  defp write_matches(dir) do
    path = Path.join(dir, "data.txt")
    lines = for n <- 1..10, do: "foo line #{n}"
    File.write!(path, Enum.join(lines, "\n") <> "\n")
    path
  end

  describe "head_limit" do
    @tag :tmp_dir
    test "caps the number of returned lines", %{tmp_dir: tmp_dir} do
      if rg_available?() do
        write_matches(tmp_dir)

        assert {:ok, output} =
                 Grep.execute(%{
                   "pattern" => "foo",
                   "path" => tmp_dir,
                   "output_mode" => "content",
                   "head_limit" => 3
                 })

        assert length(String.split(output, "\n")) == 3
      end
    end
  end

  describe "offset" do
    @tag :tmp_dir
    test "skips the first N matching lines", %{tmp_dir: tmp_dir} do
      if rg_available?() do
        write_matches(tmp_dir)

        assert {:ok, output} =
                 Grep.execute(%{
                   "pattern" => "foo",
                   "path" => tmp_dir,
                   "output_mode" => "content",
                   "offset" => 2,
                   "head_limit" => 3
                 })

        lines = String.split(output, "\n")
        assert length(lines) == 3
        assert Enum.any?(lines, &String.contains?(&1, "foo line 3"))
        refute Enum.any?(lines, &String.contains?(&1, "foo line 1"))
        refute Enum.any?(lines, &String.contains?(&1, "foo line 2"))
      end
    end
  end

  describe "count mode" do
    @tag :tmp_dir
    test "reports the true match count regardless of head_limit", %{tmp_dir: tmp_dir} do
      if rg_available?() do
        path = write_matches(tmp_dir)

        assert {:ok, output} =
                 Grep.execute(%{
                   "pattern" => "foo",
                   "path" => tmp_dir,
                   "output_mode" => "count",
                   "head_limit" => 3
                 })

        assert output =~ "#{path}:10"
      end
    end
  end

  describe "no matches" do
    @tag :tmp_dir
    test "reports when nothing matches", %{tmp_dir: tmp_dir} do
      if rg_available?() do
        write_matches(tmp_dir)

        assert {:ok, output} =
                 Grep.execute(%{"pattern" => "zzz_no_such_token", "path" => tmp_dir})

        assert output =~ "No matches found."
      end
    end
  end

  describe "validation" do
    test "returns error when pattern is missing" do
      assert {:error, msg} = Grep.execute(%{"path" => "."})
      assert msg =~ "pattern"
    end
  end
end
