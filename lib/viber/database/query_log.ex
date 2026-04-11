defmodule Viber.Database.QueryLog do
  @moduledoc """
  Ecto schema for the query audit log.
  Every SQL query executed through Viber tools is recorded.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "query_log" do
    field(:session_id, :string)
    field(:connection_name, :string)
    field(:query, :string)
    field(:query_type, :string)
    field(:execution_time_ms, :integer)
    field(:row_count, :integer)
    field(:status, :string, default: "success")
    field(:error_message, :string)
    field(:user_confirmed, :boolean, default: false)

    timestamps(updated_at: false)
  end

  @fields ~w(session_id connection_name query query_type execution_time_ms row_count status error_message user_confirmed)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @fields)
    |> validate_required([:query])
  end
end
