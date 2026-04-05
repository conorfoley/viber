defmodule Viber.Runtime.PermissionsTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.Permissions

  test "read_only mode denies write tools" do
    policy =
      Permissions.new_policy(:read_only)
      |> Permissions.register_tool("write_file", :workspace_write)

    assert {:deny, reason} = Permissions.check(policy, "write_file", "{}")
    assert reason =~ "requires workspace-write permission"
  end

  test "workspace_write mode allows write, denies bash" do
    policy =
      Permissions.new_policy(:workspace_write)
      |> Permissions.register_tool("write_file", :workspace_write)
      |> Permissions.register_tool("bash", :danger_full_access)

    assert :allow = Permissions.check(policy, "write_file", "{}")
    assert {:deny, reason} = Permissions.check(policy, "bash", "{}")
    assert reason =~ "requires danger-full-access permission"
  end

  test "danger_full_access allows everything" do
    policy =
      Permissions.new_policy(:danger_full_access)
      |> Permissions.register_tool("write_file", :workspace_write)
      |> Permissions.register_tool("bash", :danger_full_access)

    assert :allow = Permissions.check(policy, "write_file", "{}")
    assert :allow = Permissions.check(policy, "bash", "{}")
  end

  test "allow mode allows everything" do
    policy = Permissions.new_policy(:allow)
    assert :allow = Permissions.check(policy, "anything", "{}")
  end

  test "mode_from_string round-trips with mode_to_string" do
    for mode <- [:read_only, :workspace_write, :danger_full_access, :prompt, :allow] do
      assert Permissions.mode_from_string(Permissions.mode_to_string(mode)) == mode
    end
  end

  test "permission ladder ordering" do
    assert Permissions.mode_rank(:read_only) < Permissions.mode_rank(:workspace_write)
    assert Permissions.mode_rank(:workspace_write) < Permissions.mode_rank(:danger_full_access)
    assert Permissions.mode_rank(:danger_full_access) < Permissions.mode_rank(:allow)
    assert Permissions.mode_rank(:prompt) < Permissions.mode_rank(:read_only)
  end
end
