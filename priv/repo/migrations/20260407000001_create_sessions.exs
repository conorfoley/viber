defmodule Viber.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :string, primary_key: true
      add :title, :string
      add :model, :string
      add :messages, :jsonb, null: false, default: "[]"
      add :usage, :jsonb, null: false, default: "{}"

      timestamps()
    end

    create index(:sessions, [:updated_at])
  end
end
