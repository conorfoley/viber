defmodule Viber.Scheduler.AlertSinkTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Viber.Scheduler.AlertSink

  test "does nothing when the sink is nil" do
    assert AlertSink.dispatch(%{name: "job"}, "output", nil) == :ok
  end

  @tag :tmp_dir
  test "appends alerts to a file sink", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "alerts.log")
    job = %{name: "disk-check"}

    capture_log(fn ->
      assert AlertSink.dispatch(job, "disk at 92%", %{"type" => "file", "path" => path}) == :ok
    end)

    contents = File.read!(path)
    assert contents =~ "disk-check"
    assert contents =~ "disk at 92%"
  end

  test "writes to the log sink" do
    log =
      capture_log(fn ->
        assert AlertSink.dispatch(%{name: "job"}, "hello", %{"type" => "log"}) == :ok
      end)

    assert log =~ "job"
  end

  test "warns on an unknown sink type" do
    log =
      capture_log(fn ->
        assert AlertSink.dispatch(%{name: "job"}, "x", %{"type" => "carrier-pigeon"}) == :ok
      end)

    assert log =~ "Unknown alert sink type"
  end
end
