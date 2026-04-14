defmodule Viber.MixProject do
  use Mix.Project

  def project do
    [
      app: :viber,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      escript: escript(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      licenses: ["AGPL-3.0-only"],
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Viber.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp escript do
    [main_module: Viber.CLI.Main]
  end

  defp aliases do
    [
      "test.live": ["test --include live"]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.6"},
      {:owl, "~> 0.12"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19"},
      {:myxql, "~> 0.7"},
      {:quantum, "~> 3.5"},
      {:file_system, "~> 1.0"},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
