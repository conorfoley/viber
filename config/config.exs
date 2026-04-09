import Config

config :viber, ecto_repos: [Viber.Repo]

config :viber, Viber.Repo,
  database: "viber_#{config_env()}",
  username: System.get_env("PGUSER") || System.get_env("USER"),
  hostname: "localhost",
  pool_size: 5

import_config "#{config_env()}.exs"
