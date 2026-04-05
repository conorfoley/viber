defmodule Viber.Tools.Builtins.JqTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.Jq

  defp jq_available?, do: not is_nil(System.find_executable("jq"))

  describe "with 'input' (JSON string)" do
    test "extracts a top-level field" do
      if jq_available?() do
        assert {:ok, result} = Jq.execute(%{"filter" => ".name", "input" => ~s({"name":"alice"})})
        assert result == ~s("alice")
      end
    end

    test "applies an array filter" do
      if jq_available?() do
        json = ~s([{"id":1},{"id":2}])
        assert {:ok, result} = Jq.execute(%{"filter" => ".[].id", "input" => json})
        assert result == "1\n2"
      end
    end

    test "returns error on invalid JSON" do
      if jq_available?() do
        assert {:error, msg} = Jq.execute(%{"filter" => ".", "input" => "not json"})
        assert msg =~ "parse error"
      end
    end

    test "returns error on invalid filter" do
      if jq_available?() do
        assert {:error, _msg} = Jq.execute(%{"filter" => "!!!bad", "input" => ~s({})})
      end
    end
  end

  describe "with 'path' (JSON file)" do
    @tag :tmp_dir
    test "reads from a JSON file", %{tmp_dir: tmp_dir} do
      if jq_available?() do
        path = Path.join(tmp_dir, "data.json")
        File.write!(path, ~s({"version":"1.2.3"}))
        assert {:ok, result} = Jq.execute(%{"filter" => ".version", "path" => path})
        assert result == ~s("1.2.3")
      end
    end

    test "returns error for missing file" do
      if jq_available?() do
        assert {:error, _msg} = Jq.execute(%{"filter" => ".", "path" => "/nonexistent/file.json"})
      end
    end
  end

  describe "validation" do
    test "returns error when both path and input are given" do
      assert {:error, msg} =
               Jq.execute(%{"filter" => ".", "path" => "x.json", "input" => ~s({})})

      assert msg =~ "not both"
    end

    test "returns error when neither path nor input is given" do
      assert {:error, msg} = Jq.execute(%{"filter" => "."})
      assert msg =~ "path"
    end

    test "returns error when filter is missing" do
      assert {:error, msg} = Jq.execute(%{"input" => ~s({})})
      assert msg =~ "filter"
    end
  end
end
