defmodule Viber.Tools.Builtins.GitTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.Git

  describe "execute/1" do
    test "runs git status" do
      assert {:ok, result} = Git.execute(%{"subcommand" => "status"})
      assert result =~ "Exit code: 0"
    end

    test "runs git log with args" do
      assert {:ok, result} = Git.execute(%{"subcommand" => "log", "args" => ["--oneline", "-1"]})
      assert result =~ "Exit code: 0"
    end

    test "returns error for missing subcommand" do
      assert {:error, msg} = Git.execute(%{})
      assert msg =~ "subcommand"
    end

    test "returns timeout info when command exceeds timeout" do
      assert {:ok, result} = Git.execute(%{"subcommand" => "status", "timeout" => 0})
      assert result =~ "timeout"
    end
  end

  describe "read_only?/1" do
    test "classifies read-only subcommands" do
      for sub <-
            ~w(status log diff show reflog shortlog describe rev-parse ls-files ls-tree blame) do
        assert Git.read_only?(sub), "expected #{sub} to be read-only"
      end
    end

    test "classifies write subcommands" do
      for sub <- ~w(add commit checkout reset push pull merge rebase branch tag stash) do
        refute Git.read_only?(sub), "expected #{sub} to NOT be read-only"
      end
    end
  end

  describe "permission_for/1" do
    test "returns :read_only for read-only subcommands" do
      assert :read_only = Git.permission_for(%{"subcommand" => "status"})
      assert :read_only = Git.permission_for(%{"subcommand" => "log"})
      assert :read_only = Git.permission_for(%{"subcommand" => "diff"})
    end

    test "returns :workspace_write for write subcommands" do
      assert :workspace_write = Git.permission_for(%{"subcommand" => "add"})
      assert :workspace_write = Git.permission_for(%{"subcommand" => "commit"})
      assert :workspace_write = Git.permission_for(%{"subcommand" => "checkout"})
    end

    test "returns :workspace_write for missing subcommand" do
      assert :workspace_write = Git.permission_for(%{})
    end
  end
end
