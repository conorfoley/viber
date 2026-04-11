defmodule Viber.Repo.Migrations.CreateQueryLog do
  use Ecto.Migration

  def change do
    create table(:query_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string
      add :connection_name, :string
      add :query, :text, null: false
      add :query_type, :string
      add :execution_time_ms, :integer
      add :row_count, :integer
      add :status, :string, null: false, default: "success"
      add :error_message, :text
      add :user_confirmed, :boolean, null: false, default: false

      timestamps(updated_at: false)
    end

    create index(:query_log, [:session_id])
    create index(:query_log, [:connection_name])
    create index(:query_log, [:inserted_at])
  end
end
