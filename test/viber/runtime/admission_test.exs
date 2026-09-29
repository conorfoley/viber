defmodule Viber.Runtime.AdmissionTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.Admission

  setup do
    name = :"admission_#{System.unique_integer([:positive])}"
    start_supervised!({Admission, name: name, limits: [work: 2]})
    {:ok, opts: [server: name]}
  end

  defp holder do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  test "refuses once the pool is full and admits again after release", %{opts: opts} do
    [a, b, c] = [holder(), holder(), holder()]

    assert :ok = Admission.acquire(:work, [holder: a] ++ opts)
    assert :ok = Admission.acquire(:work, [holder: b] ++ opts)
    assert {:error, :busy} = Admission.acquire(:work, [holder: c] ++ opts)

    assert :ok = Admission.release(:work, [holder: a] ++ opts)
    assert :ok = Admission.acquire(:work, [holder: c] ++ opts)
    assert %{work: %{in_use: 2, limit: 2}} = Admission.stats(opts)
  end

  test "a slot is freed when its holder exits", %{opts: opts} do
    a = holder()
    ref = Process.monitor(a)

    assert :ok = Admission.acquire(:work, [holder: a] ++ opts)
    assert :ok = Admission.acquire(:work, [holder: holder()] ++ opts)
    send(a, :stop)
    assert_receive {:DOWN, ^ref, :process, _, _}

    assert %{work: %{in_use: 1}} = Admission.stats(opts)
    assert :ok = Admission.acquire(:work, [holder: holder()] ++ opts)
  end

  test "unconfigured pools are unlimited", %{opts: opts} do
    for _ <- 1..10, do: assert(:ok = Admission.acquire(:other, opts))
    refute Map.has_key?(Admission.stats(opts), :other)
  end

  test "transfer moves the slot to another process", %{opts: opts} do
    target = holder()
    ref = Process.monitor(target)

    assert :ok = Admission.acquire(:work, opts)
    assert :ok = Admission.transfer(:work, target, opts)
    assert {:error, :not_held} = Admission.transfer(:work, target, opts)
    assert :ok = Admission.release(:work, opts)
    assert %{work: %{in_use: 1}} = Admission.stats(opts)

    send(target, :stop)
    assert_receive {:DOWN, ^ref, :process, _, _}
    assert %{work: %{in_use: 0}} = Admission.stats(opts)
  end

  test "run/3 releases the slot after the function returns or raises", %{opts: opts} do
    assert :done = Admission.run(:work, fn -> :done end, opts)
    assert_raise RuntimeError, fn -> Admission.run(:work, fn -> raise "boom" end, opts) end
    assert %{work: %{in_use: 0}} = Admission.stats(opts)
  end

  test "run/3 returns busy without calling the function when full", %{opts: opts} do
    Admission.acquire(:work, [holder: holder()] ++ opts)
    Admission.acquire(:work, [holder: holder()] ++ opts)

    assert {:error, :busy} = Admission.run(:work, fn -> flunk("should not run") end, opts)
  end
end
