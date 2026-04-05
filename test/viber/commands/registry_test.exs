defmodule Viber.Commands.RegistryTest do
  use ExUnit.Case, async: true

  alias Viber.Commands.Registry

  test "all/0 returns non-empty list" do
    assert length(Registry.all()) > 0
  end

  test "get/1 finds known commands" do
    assert {:ok, %{name: "help"}} = Registry.get("help")
    assert {:ok, %{name: "status"}} = Registry.get("status")
    assert {:ok, %{name: "compact"}} = Registry.get("compact")
  end

  test "get/1 returns :error for unknown" do
    assert :error = Registry.get("nonexistent")
  end

  test "names/0 returns sorted list" do
    names = Registry.names()
    assert is_list(names)
    assert names == Enum.sort(names)
    assert "help" in names
  end

  test "each spec has required fields" do
    for spec <- Registry.all() do
      assert is_binary(spec.name)
      assert is_list(spec.aliases)
      assert is_binary(spec.description)
      assert is_binary(spec.usage)
      assert spec.category in [:session, :config, :info, :project]
      assert is_atom(spec.handler)
    end
  end
end
