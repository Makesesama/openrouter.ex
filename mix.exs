defmodule Openrouter.MixProject do
  use Mix.Project

  def project do
    [
      app: :openrouter,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Openrouter",
      source_url: "https://github.com/Makesesama/openrouter.ex"
    ]
  end

  defp description do
    """
    OpenRouter-focused AI SDK for Elixir with production-grade reliability,
    seamless Phoenix integration, and support for agentic workflows.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/Makesesama/openrouter.ex",
        "OpenRouter" => "https://openrouter.ai"
      }
    ]
  end

  defp docs do
    [
      main: "Openrouter",
      extras: ["README.md", "DESIGN.md"]
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
      # HTTP client with streaming support
      {:req, "~> 0.5"},

      # JSON encoding/decoding
      {:jason, "~> 1.4"},

      # Observability and metrics
      {:telemetry, "~> 1.2"},

      # Optional dependencies
      {:ecto, "~> 3.11", optional: true},

      # Development and testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
