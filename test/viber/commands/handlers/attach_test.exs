defmodule Viber.Commands.Handlers.AttachTest do
  use ExUnit.Case, async: true

  alias Viber.Commands.Handlers.Attach
  alias Viber.Runtime.Session

  setup do
    tmp = System.tmp_dir!() |> Path.join("attach_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp)
    {:ok, session} = Session.start_link(id: "attach-test-#{:rand.uniform(1_000_000)}")
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp, session: session}
  end

  test "returns error when no args given", %{session: session, tmp: tmp} do
    context = %{session: session, project_root: tmp}
    assert {:error, msg} = Attach.execute([], context)
    assert msg =~ "Usage: /attach"
  end

  test "returns error when no session in context", %{tmp: tmp} do
    context = %{session: nil, project_root: tmp}
    assert {:error, "No active session"} = Attach.execute(["file.txt"], context)
  end

  test "returns error when session key is missing", %{tmp: tmp} do
    context = %{project_root: tmp}
    assert {:error, "No active session"} = Attach.execute(["file.txt"], context)
  end

  test "attaches a single file to session", %{session: session, tmp: tmp} do
    path = Path.join(tmp, "hello.txt")
    File.write!(path, "hello world")

    context = %{session: session, project_root: tmp}
    assert {:ok, msg} = Attach.execute(["hello.txt"], context)
    assert msg =~ "Attached 1 file(s)"
    assert msg =~ path

    messages = Session.get_messages(session)
    assert length(messages) == 1
    [%{role: :user, blocks: [{:text, content}], usage: nil}] = messages
    assert content =~ "hello world"
    assert content =~ "<file: #{path}>"
  end

  test "attaches multiple files in one session message", %{session: session, tmp: tmp} do
    File.write!(Path.join(tmp, "a.txt"), "aaa")
    File.write!(Path.join(tmp, "b.txt"), "bbb")
    path_a = Path.join(tmp, "a.txt")
    path_b = Path.join(tmp, "b.txt")

    context = %{session: session, project_root: tmp}
    assert {:ok, msg} = Attach.execute(["a.txt", "b.txt"], context)
    assert msg =~ "Attached 2 file(s)"

    messages = Session.get_messages(session)
    assert length(messages) == 1
    [%{role: :user, blocks: [{:text, content}]}] = messages
    assert content =~ "<file: #{path_a}>"
    assert content =~ "<file: #{path_b}>"
  end

  test "attaches files matched by glob pattern", %{session: session, tmp: tmp} do
    for name <- ~w[x.ex y.ex z.ex] do
      File.write!(Path.join(tmp, name), name)
    end

    context = %{session: session, project_root: tmp}
    assert {:ok, msg} = Attach.execute(["*.ex"], context)
    assert msg =~ "Attached 3 file(s)"

    messages = Session.get_messages(session)
    assert length(messages) == 1
  end

  test "returns error when glob matches no files", %{session: session, tmp: tmp} do
    context = %{session: session, project_root: tmp}
    assert {:error, _} = Attach.execute(["*.nonexistent"], context)

    assert Session.get_messages(session) == []
  end

  test "partial failure: succeeds when at least one file is resolved", %{
    session: session,
    tmp: tmp
  } do
    path = Path.join(tmp, "good.txt")
    File.write!(path, "good content")

    context = %{session: session, project_root: tmp}
    assert {:ok, msg} = Attach.execute(["good.txt", "missing.txt"], context)
    assert msg =~ "Attached 1 file(s)"
    assert msg =~ "Error"

    messages = Session.get_messages(session)
    assert length(messages) == 1
  end

  test "all-fail returns error without adding session message", %{session: session, tmp: tmp} do
    context = %{session: session, project_root: tmp}
    assert {:error, _} = Attach.execute(["nope.txt", "also_nope.txt"], context)
    assert Session.get_messages(session) == []
  end

  test "falls back to cwd when project_root not in context", %{session: session, tmp: tmp} do
    path = Path.join(tmp, "cwd_test.txt")
    File.write!(path, "cwd content")

    context = %{session: session, project_root: tmp}
    assert {:ok, _} = Attach.execute([path], context)
  end
end
