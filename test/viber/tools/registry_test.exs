defmodule Viber.Tools.RegistryTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.{Registry, Spec}

  describe "get/1" do
    test "returns spec for each known tool" do
      for name <- Registry.list_names() do
        assert {:ok, %Spec{name: ^name}} = Registry.get(name)
      end
    end

    test "returns :error for unknown tool" do
      assert :error = Registry.get("nonexistent_tool")
    end
  end

  describe "list_names/0" do
    test "returns all tool names sorted" do
      names = Registry.list_names()
      assert length(names) == 8
      assert names == Enum.sort(names)
    end
  end

  describe "normalize_name/1" do
    test "handles case variations" do
      assert Registry.normalize_name("Bash") == "bash"
      assert Registry.normalize_name("READ_FILE") == "read_file"
    end

    test "handles hyphens" do
      assert Registry.normalize_name("read-file") == "read_file"
      assert Registry.normalize_name("Web-Fetch") == "web_fetch"
    end

    test "trims whitespace" do
      assert Registry.normalize_name("  bash  ") == "bash"
    end
  end

  describe "builtin_specs/0" do
    test "returns non-empty list" do
      specs = Registry.builtin_specs()
      assert length(specs) > 0
    end

    test "each spec has valid input_schema" do
      for spec <- Registry.builtin_specs() do
        assert spec.input_schema["type"] == "object"
        assert is_map(spec.input_schema["properties"])
      end
    end
  end

  describe "to_tool_definition/1" do
    test "converts spec to API tool definition" do
      {:ok, spec} = Registry.get("bash")
      td = Spec.to_tool_definition(spec)
      assert td.name == "bash"
      assert td.description == spec.description
      assert td.input_schema == spec.input_schema
    end
  end
end
