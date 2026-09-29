import Config

config :viber, ecto_repos: [Viber.Repo]

config :viber, :admission, gateway: 4, scheduler: 2, server: 8, sub_agent: 4

config :viber, :browser_toolset,
  auto_activate: true,
  action_timeout_ms: 30_000

config :viber, Viber.Repo,
  database: "viber_#{config_env()}",
  username: System.get_env("PGUSER") || System.get_env("USER"),
  hostname: "localhost",
  pool_size: 5

import_config "#{config_env()}.exs"
