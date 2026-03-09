defmodule AccountabilityWorkflow.MixProject do
  use Mix.Project

  def project do
    [
      app: :accountability_workflow,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AccountabilityWorkflow.Application, []}
    ]
  end

  defp deps do
    [
      {:ash_durable_reactor, path: "../.."},
      {:ash, "~> 3.19"}
    ]
  end
end
