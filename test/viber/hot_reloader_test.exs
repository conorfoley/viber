defmodule Viber.HotReloaderTest do
  use ExUnit.Case, async: false

  alias Viber.Commands.Handlers.Reload
  alias Viber.HotReloader

  @project_root File.cwd!()

  describe "reload/1 — successful compile" do
    test "returns {:ok, modules} with a list of atoms" do
      assert {:ok, modules} = HotReloader.reload(@project_root)
      assert is_list(modules)
      assert Enum.all?(modules, &is_atom/1)
    end

    test "falls back to inline run_reload when GenServer is not running" do
      refute Process.whereis(HotReloader)
      assert {:ok, _modules} = HotReloader.reload(@project_root)
    end
  end

  describe "reload/1 — compilation failure" do
    test "returns {:error, output} for a directory without a Mix project" do
      tmp = System.tmp_dir!() |> Path.join("viber_hr_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:error, output} = HotReloader.reload(tmp)
      assert is_binary(output)
      assert byte_size(output) > 0
    end
  end

  describe "Handlers.Reload.execute/2" do
    test "returns {:ok, message} containing 'module' on success" do
      assert {:ok, msg} = Reload.execute([], %{project_root: @project_root})
      assert is_binary(msg)
      assert msg =~ "module"
    end

    test "falls back to File.cwd! when project_root absent from context" do
      assert {:ok, _msg} = Reload.execute([], %{})
    end

    test "returns {:error, message} prefixed with 'Compilation failed' on error" do
      tmp = System.tmp_dir!() |> Path.join("viber_hr_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:error, msg} = Reload.execute([], %{project_root: tmp})
      assert msg =~ "Compilation failed"
    end

    test "returns 'No modules reloaded' message when nothing changed" do
      assert {:ok, msg} = Reload.execute([], %{project_root: @project_root})
      assert is_binary(msg)

      if msg =~ "No modules reloaded" do
        assert msg == "No modules reloaded (nothing changed)."
      else
        assert msg =~ ~r/Recompiled \d+ module\(s\):/
      end
    end

    test "output includes module names when modules were reloaded" do
      assert {:ok, msg} = Reload.execute([], %{project_root: @project_root})

      unless msg =~ "No modules reloaded" do
        assert msg =~ ~r/Recompiled \d+ module\(s\): .+/
        assert msg =~ "Viber."
      end
    end
  end

  describe "Registry — /reload command registration" do
    test "reload command is registered with correct metadata" do
      assert {:ok, spec} = Viber.Commands.Registry.get("reload")
      assert spec.name == "reload"
      assert spec.category == :project
      assert spec.handler == Viber.Commands.Handlers.Reload
      assert is_binary(spec.description)
      assert spec.usage == "/reload"
    end
  end
end
