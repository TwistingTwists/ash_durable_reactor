defmodule AshPersistence.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_persistence,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AshPersistence.Application, []}
    ]
  end

  defp deps do
    [
      {:ash_durable_reactor, path: "../.."},
      {:ash, "~> 3.19"},
      {:ash_sqlite, "~> 0.2.16"},
      {:ash_postgres, "~> 2.7"}
    ]
  end

  defp elixirc_paths(_), do: ["lib"]
end
