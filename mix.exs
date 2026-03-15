defmodule AshDurableReactor.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_durable_reactor,
      version: "0.2.0",
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
      mod: {AshDurableReactor.Application, []}
    ]
  end

  defp deps do
    [
      {:reactor, "~> 1.0"},
      {:ash, "~> 3.19"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
