defmodule Viber.Commands.DispatcherTest do
  use ExUnit.Case, async: false

  alias Viber.Commands.{Dispatcher, Result}
  alias Viber.Runtime.{Event, Session}

  setup do
    id = "disp-#{System.unique_integer([:positive])}"

    opts = [
      id: id,
      model: "sonnet",
      project_root: File.cwd!(),
      name: {:via, Registry, {Viber.SessionRegistry, id}}
    ]

    {:ok, pid} = DynamicSupervisor.start_child(Viber.SessionSupervisor, {Session, opts})

    on_exit(fn ->
      DynamicSupervisor.terminate_child(Viber.SessionSupervisor, pid)
    end)

    {:ok, session: pid, session_id: id}
  end

  test "unknown command returns {:error, {:unknown_command, name}}" do
    assert {:error, {:unknown_command, "no-such"}} =
             Dispatcher.invoke(nil, "no-such", [], %{})
  end

  test "/help returns text-only result", %{session: pid} do
    assert {:ok, %Result{text: text, events: [], state_patch: %{}}} =
             Dispatcher.invoke(pid, "help", [], %{model: "sonnet"})

    assert is_binary(text)
    assert text =~ "help"
  end

  test "/clear emits :session_cleared event and patches state", %{session: pid} do
    assert {:ok, %Result{events: events, state_patch: patch}} =
             Dispatcher.invoke(pid, "clear", [], %{})

    assert Map.get(patch, :cleared) == true
    assert Enum.any?(events, fn %Event{type: t} -> t == :session_cleared end)
  end

  test "/model <name> sets session model and emits :model_changed", %{session: pid} do
    assert {:ok, %Result{events: events, state_patch: patch}} =
             Dispatcher.invoke(pid, "model", ["haiku"], %{model: "sonnet"})

    assert Map.get(patch, :model) == "haiku"
    assert Session.get_model(pid) == "haiku"

    assert Enum.any?(events, fn %Event{type: :model_changed, payload: %{model: m}} ->
             m == "haiku"
           end)
  end

  test "/model list does not switch model or emit model_changed", %{session: pid} do
    Session.set_model(pid, "sonnet")

    assert {:ok, %Result{events: events, state_patch: patch}} =
             Dispatcher.invoke(pid, "model", ["list"], %{model: "sonnet"})

    refute Map.has_key?(patch, :model)
    assert Session.get_model(pid) == "sonnet"
    refute Enum.any?(events, fn %Event{type: t} -> t == :model_changed end)
  end

  test "handler {:retry, input} converts to state_patch.retry_input", %{session: pid} do
    Session.add_message(pid, %{role: :user, blocks: [{:text, "hello"}], usage: nil})
    Session.add_message(pid, %{role: :assistant, blocks: [{:text, "hi"}], usage: nil})

    assert {:ok, %Result{state_patch: %{retry_input: "hello"}}} =
             Dispatcher.invoke(pid, "retry", [], %{})
  end

  test "handler errors propagate", %{session: pid} do
    assert {:error, _reason} = Dispatcher.invoke(pid, "retry", [], %{})
  end
end
