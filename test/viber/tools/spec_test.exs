defmodule Viber.Tools.SpecTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Spec

  describe "effective_permission/2" do
    test "returns static permission when permission_fn is nil" do
      spec = %Spec{
        name: "test",
        description: "test",
        input_schema: %{},
        permission: :workspace_write,
        permission_fn: nil
      }

      assert :workspace_write = Spec.effective_permission(spec, %{})
    end

    test "uses permission_fn when provided" do
      spec = %Spec{
        name: "test",
        description: "test",
        input_schema: %{},
        permission: :workspace_write,
        permission_fn: fn
          %{"mode" => "read"} -> :read_only
          _ -> :workspace_write
        end
      }

      assert :read_only = Spec.effective_permission(spec, %{"mode" => "read"})
      assert :workspace_write = Spec.effective_permission(spec, %{"mode" => "write"})
    end

    test "works with git tool permission_for function" do
      spec = %Spec{
        name: "git",
        description: "git",
        input_schema: %{},
        permission: :workspace_write,
        permission_fn: &Viber.Tools.Builtins.Git.permission_for/1
      }

      assert :read_only = Spec.effective_permission(spec, %{"subcommand" => "status"})
      assert :workspace_write = Spec.effective_permission(spec, %{"subcommand" => "commit"})
    end
  end

  describe "effect/2" do
    test "read_only permission is a read, anything else a write" do
      base = %Spec{name: "t", description: "t", input_schema: %{}, permission: :read_only}
      assert Spec.effect(base, %{}) == :read
      assert Spec.effect(%{base | permission: :workspace_write}, %{}) == :write
    end

    test "follows permission_fn" do
      spec = %Spec{
        name: "git",
        description: "git",
        input_schema: %{},
        permission: :workspace_write,
        permission_fn: &Viber.Tools.Builtins.Git.permission_for/1
      }

      assert Spec.effect(spec, %{"subcommand" => "log"}) == :read
      assert Spec.effect(spec, %{"subcommand" => "push"}) == :write
    end

    test "effect_fn overrides the default" do
      spec = %Spec{
        name: "t",
        description: "t",
        input_schema: %{},
        permission: :danger_full_access,
        effect_fn: fn _ -> :read end
      }

      assert Spec.effect(spec, %{}) == :read
    end
  end

  describe "to_tool_definition/1" do
    test "converts spec to tool definition" do
      spec = %Spec{
        name: "my_tool",
        description: "A tool",
        input_schema: %{"type" => "object"},
        permission: :read_only
      }

      defn = Spec.to_tool_definition(spec)
      assert defn.name == "my_tool"
      assert defn.description == "A tool"
      assert defn.input_schema == %{"type" => "object"}
    end
  end
end
