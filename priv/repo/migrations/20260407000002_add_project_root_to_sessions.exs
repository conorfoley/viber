defmodule Viber.Repo.Migrations.AddProjectRootToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :project_root, :string
    end
  end
end
