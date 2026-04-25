defmodule Viber.Runtime.Permissions.BrokerTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.Event
  alias Viber.Runtime.Permissions.Broker

  setup do
    name = :"broker_#{System.unique_integer([:positive])}"
    {:ok, pid} = Broker.start_link(name: name)
    {:ok, broker: name, pid: pid}
  end

  test "request/resolve round-trip with :allow", %{broker: broker} do
    parent = self()

    handler = fn %Event{type: :permission_request, payload: %{request_id: rid}} = e ->
      send(parent, {:emitted, rid, e})
      :ok
    end

    task =
      Task.async(fn ->
        Broker.request("sess-1", "bash", "{}", handler, server: broker, timeout: 1_000)
      end)

    assert_receive {:emitted, rid, %Event{type: :permission_request, payload: payload}}, 500
    assert payload.tool == "bash"
    assert payload.request_id == rid
    assert Broker.pending(server: broker) == [rid]

    :ok = Broker.resolve(rid, :allow, server: broker)
    assert :allow = Task.await(task, 1_000)
    assert Broker.pending(server: broker) == []
  end

  test "always_allow decision propagates", %{broker: broker} do
    parent = self()
    handler = fn %Event{payload: %{request_id: rid}} -> send(parent, {:rid, rid}) && :ok end

    task =
      Task.async(fn ->
        Broker.request(nil, "write_file", "{}", handler, server: broker, timeout: 1_000)
      end)

    assert_receive {:rid, rid}, 500
    :ok = Broker.resolve(rid, :always_allow, server: broker)
    assert :always_allow = Task.await(task, 1_000)
  end

  test "deny decision propagates", %{broker: broker} do
    parent = self()
    handler = fn %Event{payload: %{request_id: rid}} -> send(parent, {:rid, rid}) && :ok end

    task =
      Task.async(fn ->
        Broker.request(nil, "bash", "{}", handler, server: broker, timeout: 1_000)
      end)

    assert_receive {:rid, rid}, 500
    :ok = Broker.resolve(rid, :deny, server: broker)
    assert :deny = Task.await(task, 1_000)
  end

  test "timeout yields :deny and clears pending", %{broker: broker} do
    handler = fn _ -> :ok end
    assert :deny = Broker.request(nil, "bash", "{}", handler, server: broker, timeout: 50)
    assert Broker.pending(server: broker) == []
  end

  test "resolve with unknown id returns :not_found", %{broker: broker} do
    assert {:error, :not_found} = Broker.resolve("missing", :allow, server: broker)
  end

  test "caller death cleans up pending entry", %{broker: broker} do
    parent = self()
    handler = fn %Event{payload: %{request_id: rid}} -> send(parent, {:rid, rid}) && :ok end

    {:ok, task_pid} =
      Task.start(fn ->
        Broker.request("sess-x", "bash", "{}", handler, server: broker, timeout: 60_000)
      end)

    assert_receive {:rid, rid}, 500
    assert rid in Broker.pending(server: broker)

    ref = Process.monitor(task_pid)
    Process.exit(task_pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^task_pid, _}, 500

    # Allow broker to process the :DOWN message.
    _ = Broker.pending(server: broker)
    assert Broker.pending(server: broker) == []
  end

  test "session-scoped resolve rejects mismatched session", %{broker: broker} do
    parent = self()
    handler = fn %Event{payload: %{request_id: rid}} -> send(parent, {:rid, rid}) && :ok end

    task =
      Task.async(fn ->
        Broker.request("sess-a", "bash", "{}", handler, server: broker, timeout: 1_000)
      end)

    assert_receive {:rid, rid}, 500

    assert {:error, :session_mismatch} =
             Broker.resolve(rid, :allow, server: broker, session_id: "sess-b")

    assert :ok = Broker.resolve(rid, :allow, server: broker, session_id: "sess-a")
    assert :allow = Task.await(task, 1_000)
  end

  test "event handler exit causes :deny and cleanup", %{broker: broker} do
    handler = fn _event -> exit(:boom) end

    assert :deny = Broker.request("sess", "bash", "{}", handler, server: broker, timeout: 1_000)
    assert Broker.pending(server: broker) == []
  end
end
