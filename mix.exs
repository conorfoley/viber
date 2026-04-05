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
      deps: deps()
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

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.6"},
      {:owl, "~> 0.12"},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
