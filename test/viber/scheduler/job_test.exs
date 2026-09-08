defmodule Viber.Scheduler.JobTest do
  use ExUnit.Case, async: true

  alias Viber.Scheduler.Job

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "nightly-report",
        "cron_expr" => "0 0 * * *",
        "type" => "query",
        "payload" => %{"sql" => "SELECT 1"}
      },
      overrides
    )
  end

  test "accepts a valid job" do
    changeset = Job.changeset(%Job{}, valid_attrs())
    assert changeset.valid?
  end

  test "requires name and cron_expr" do
    changeset = Job.changeset(%Job{}, %{})
    refute changeset.valid?
    assert %{name: _, cron_expr: _} = errors_on(changeset)
  end

  test "rejects an unknown type" do
    changeset = Job.changeset(%Job{}, valid_attrs(%{"type" => "bogus"}))
    refute changeset.valid?
    assert Map.has_key?(errors_on(changeset), :type)
  end

  test "accepts each supported type" do
    for type <- ~w(query script health_check) do
      assert Job.changeset(%Job{}, valid_attrs(%{"type" => type})).valid?
    end
  end

  test "rejects an invalid cron expression" do
    changeset = Job.changeset(%Job{}, valid_attrs(%{"cron_expr" => "not a cron"}))
    refute changeset.valid?
    assert "is not a valid cron expression" in errors_on(changeset).cron_expr
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
