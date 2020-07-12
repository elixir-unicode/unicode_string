defmodule UnicodeString.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :unicode_string,
      version: @version,
      elixir: "~> 1.8",
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
        plt_add_apps: ~w(mix sweet_xml)a
      ]
    ]
  end

  defp description do
    """
    Functions to perform Unicode string operations like case
    folding, case-insensitive equality as well as word, line,
    grapheme and sentence breaking.
    """
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache 2.0"],
      logo: "logo.png",
      links: links(),
      files: [
        "lib",
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
      {:unicode_set, "~> 0.8.0"},
      {:sweet_xml, "~> 0.6", runtime: false},
      {:benchee, "~> 1.0", only: :dev, optional: true},
      {:ex_doc, "~> 0.19", only: [:release, :dev], optional: true},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false, optional: true}
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/elixir-unicode/unicode_string",
      "Readme" => "https://github.com/elixir-unicode/unicode_string/blob/v#{@version}/README.md",
      "Changelog" => "https://github.com/elixir-unicode/unicode_string/blob/v#{@version}/CHANGELOG.md"
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
      skip_undefined_reference_warnings_on: ["changelog"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "src", "test"]
  defp elixirc_paths(:dev), do: ["lib", "mix", "src", "bench"]
  defp elixirc_paths(_), do: ["lib", "src"]
end
