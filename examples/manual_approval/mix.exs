defmodule ManualApproval.MixProject do
  use Mix.Project

  def project do
    [
      app: :manual_approval,
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
      mod: {ManualApproval.Application, []}
    ]
  end

  defp deps do
    [
      {:ash_durable_reactor, path: "../.."}
    ]
  end

  defp elixirc_paths(_), do: ["lib"]
end
