defmodule Unicode.String.MixProject do
  use Mix.Project

  @version "1.3.0"

  def project do
    [
      app: :unicode_string,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      name: "Unicode String",
      source_url: "https://github.com/elixir-unicode/unicode_string",
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore_warnings",
        plt_add_apps: ~w(mix sweet_xml)a
        # Wait until ex_cldr 2.38
        # flags: [:underspecs]
      ]
    ]
  end

  defp description do
    """
    Unicode locale-aware case folding, case mapping (upcase, downcase and titlecase)
    case-insensitive equality as well as word, line, grapheme and sentence
    breaking and streaming.
    """
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      logo: "logo.png",
      links: links(),
      files: [
        "lib",
        "priv",
        "logo.png",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:unicode_set, path: "../unicode_set"},
      # {:unicode, "~> 1.19"},
      # {:unicode_set, "~> 1.3"},

      {:ex_cldr, "~> 2.37", optional: true},
      {:jason, "~> 1.0", optional: true},
      {:sweet_xml, "~> 0.7", runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.0", only: :dev, optional: true},
      {:ex_doc, "~> 0.23", only: [:dev, :release], optional: true, runtime: false}
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/elixir-unicode/unicode_string",
      "Readme" => "https://github.com/elixir-unicode/unicode_string/blob/v#{@version}/README.md",
      "Changelog" =>
        "https://github.com/elixir-unicode/unicode_string/blob/v#{@version}/CHANGELOG.md"
    }
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      logo: "logo.png",
      extras: [
        "README.md",
        "LICENSE.md",
        "CHANGELOG.md"
      ],
      skip_undefined_reference_warnings_on: ["changelog", "CHANGELOG.md"],
      formatters: ["html"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "src", "test"]
  defp elixirc_paths(:dev), do: ["lib", "mix", "src", "bench"]
  defp elixirc_paths(_), do: ["lib", "src"]
end
