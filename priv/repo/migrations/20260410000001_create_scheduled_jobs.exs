defmodule Viber.Repo.Migrations.CreateScheduledJobs do
  use Ecto.Migration

  def change do
    create table(:scheduled_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :cron_expr, :string, null: false
      add :type, :string, null: false, default: "query"
      add :payload, :jsonb, null: false, default: "{}"
      add :database, :string
      add :alert_rule, :jsonb
      add :alert_sink, :jsonb
      add :enabled, :boolean, null: false, default: true
      add :last_run_at, :utc_datetime
      add :last_status, :string

      timestamps()
    end

    create unique_index(:scheduled_jobs, [:name])
  end
end
