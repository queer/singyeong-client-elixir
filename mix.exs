defmodule Singyeong.MixProject do
  use Mix.Project

  @version "0.2.0"
  @repo_url "https://github.com/queer/singyeong-client-elixir"

  def project do
    [
      app: :singyeong,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      package: [
        maintainers: ["amy"],
        links: %{"GitHub" => @repo_url},
        licenses: ["MIT"],
      ],
      description: "Elixir client for singyeong.",

      # Docs
      name: "singyeong",
      docs: [
        homepage_url: "https://github.com/queer/singyeong-client-elixir",
        source_url: @repo_url,
        extras: [
          "README.md",
        ]
      ],
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl]
    ]
  end

  defp deps do
    [
      {:gun, "~> 1.3"},
      {:typed_struct, "~> 0.2.1"},
      {:gen_stage, "~> 1.0"},
      {:httpoison, "~> 1.7"},
      {:jason, "~> 1.2"},

      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
    ]
  end
end
