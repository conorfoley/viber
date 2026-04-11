defmodule Viber.Scheduler.Job do
  @moduledoc """
  Ecto schema for persisted scheduled job definitions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "scheduled_jobs" do
    field(:name, :string)
    field(:cron_expr, :string)
    field(:type, :string, default: "query")
    field(:payload, :map, default: %{})
    field(:database, :string)
    field(:alert_rule, :map)
    field(:alert_sink, :map)
    field(:enabled, :boolean, default: true)
    field(:last_run_at, :utc_datetime)
    field(:last_status, :string)

    timestamps()
  end

  @required ~w(name cron_expr type payload)a
  @optional ~w(database alert_rule alert_sink enabled last_run_at last_status)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(job, attrs) do
    job
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:name)
    |> validate_inclusion(:type, ~w(query script health_check))
    |> validate_cron_expr()
  end

  defp validate_cron_expr(changeset) do
    case get_change(changeset, :cron_expr) do
      nil ->
        changeset

      expr ->
        case Crontab.CronExpression.Parser.parse(expr) do
          {:ok, _} -> changeset
          {:error, _} -> add_error(changeset, :cron_expr, "is not a valid cron expression")
        end
    end
  end
end
