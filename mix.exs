defmodule Parselet.MixProject do
  use Mix.Project

  def project do
    [
      app: :parselet,
      version: "0.1.2",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_paths: ["test"],
      package:       package(),

      # Docs
      name:         "Parselet",
      description:  "A declarative text parsing library for Elixir",
      homepage_url: "http://github.com/saleyn/parselet",
      authors:      ["Serge Aleynikov"],
      docs:         [
        main: "readme",
        extras: ["README.md", "API.md", "DEVELOPER_GUIDE.md"],
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
      links:    %{"GitHub" => "https://github.com/saleyn/parselet"},
      files:    ~w(lib mix.exs Makefile *.md test)
    ]
  end
end
