defmodule Viber.Repo do
  use Ecto.Repo,
    otp_app: :viber,
    adapter: Ecto.Adapters.Postgres
end
