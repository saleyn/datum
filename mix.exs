defmodule Datum.MixProject do
  use Mix.Project

  def project do
    [
      app: :datum,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_paths: ["test"],
      package:       package(),

      # Docs
      name:         "Datum",
      description:  "A declarative text parsing library for Elixir",
      homepage_url: "http://github.com/saleyn/datum",
      authors:      ["Serge Aleynikov"],
      docs:         [
        main:       "Datum.Component", # The main page in the docs
        extras:     ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :timex]
    ]
  end

  defp deps do
    [
      {:timex, "~> 3.7", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
    ]
  end

  defp package() do
    [
      # These are the default files included in the package
      licenses: ["MIT"],
      links:    %{"GitHub" => "https://github.com/saleyn/datum"},
      files:    ~w(lib mix.exs Makefile *.md test)
    ]
  end
end
