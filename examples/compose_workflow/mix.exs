defmodule ComposeWorkflow.MixProject do
  use Mix.Project

  def project do
    [
      app: :compose_workflow,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ComposeWorkflow.Application, []}
    ]
  end

  defp deps do
    [
      {:ash_durable_reactor, path: "../.."}
    ]
  end

  defp elixirc_paths(_), do: ["lib"]
end
