defmodule VayneMetricMysql.MixProject do
  use Mix.Project

  def project do
    [
      app: :vayne_metric_mysql,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mariaex, "~> 0.8.4"},
      {:credo, "~> 0.9", only: [:dev, :test], runtime: false},
      {:vayne, github: "mon-suit/vayne_core", only: [:dev, :test], runtime: false},
    ]
  end
end
