defmodule Unicode.String.MixProject do
  use Mix.Project

  @version "2.3.1"

  def project do
    [
      app: :unicode_string,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      compilers: maybe_elixir_make() ++ Mix.compilers(),
      make_makefile: "c_src/Makefile",
      make_clean: ["clean"],
      name: "Unicode String",
      source_url: "https://github.com/elixir-unicode/unicode_string",
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [
        summary: [threshold: 90],
        ignore_modules: coverage_ignore_modules()
      ],
      dialyzer: [
        plt_add_apps: ~w(mix sweet_xml)a,
        flags: [:underspecs]
      ]
    ]
  end

  # Modules excluded from `mix test --cover` so coverage reflects the runtime
  # library, not build tooling (Mix tasks, dictionary/data generators) or the
  # test harness (conformance-data parsers under `test/support`).
  #
  # The three compile-time modules cannot report runtime coverage at all.
  # `Unicode.String.Dfa` is a `__using__` macro whose code is injected into the
  # four engines and measured there; `…Dfa.Builder` reads the state machine data
  # while the engines compile; `…ExtendedPictographic` builds a guard expression
  # that is inlined into its callers. All three report 0% however heavily the
  # code they generate is exercised.
  defp coverage_ignore_modules do
    [
      ~r/^Mix\.Tasks\./,
      Unicode.String.TestDataParser,
      Unicode.String.IcuRbbiParser,
      Unicode.String.Dfa,
      Unicode.String.Dfa.Builder,
      Unicode.String.ExtendedPictographic
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
        # Listed individually rather than as "priv" so that a locally built
        # `priv/*.so` from the opt-in ICU NIF is never packaged. The NIF is
        # compiled by the consumer when they ask for it.
        "priv/dictionaries",
        "priv/segments",
        "priv/pri555",
        "logo.png",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*",
        "conformance.md",
        "guides"
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
      {:unicode_set, github: "elixir-unicode/unicode_set", branch: "unicode-18"},
      # Unicode 18 draft data. Transitive via :unicode_set, so this needs
      # `override: true` to win over the hex requirement.
      {:unicode, github: "elixir-unicode/unicode", branch: "unicode-18", override: true},
      {:trie, "~> 2.0"},
      {:localize, "~> 1.0-rc", optional: true},
      {:jason, "~> 1.0", optional: true},
      {:sweet_xml, "~> 0.7", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false, optional: true},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.0", only: :dev, optional: true, runtime: false},
      {:elixir_make, "~> 0.4", runtime: false, optional: true},
      {:ex_doc, "~> 0.23", only: [:dev, :release], optional: true, runtime: false}
    ]
  end

  # The ICU NIF is opt-in, so the :elixir_make compiler is only added when it
  # has been asked for. Without this a default build would require ICU headers
  # and a C toolchain, which most users of a pure Elixir library will not have.
  defp maybe_elixir_make do
    if nif_enabled?() do
      [:elixir_make]
    else
      []
    end
  end

  defp nif_enabled? do
    String.downcase(System.get_env("UNICODE_STRING_NIF", "false")) == "true" ||
      Application.get_env(:unicode_string, :nif, false) == true
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
      formatters: ["html", "markdown"],
      extras: [
        "README.md",
        "guides/introduction.md",
        "guides/grapheme_break.md",
        "guides/word_break.md",
        "guides/sentence_break.md",
        "guides/line_break.md",
        "guides/casing.md",
        "conformance.md",
        "LICENSE.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ],
      groups_for_modules: groups_for_modules(),
      skip_undefined_reference_warnings_on: ["changelog", "CHANGELOG.md"]
    ]
  end

  # `Unicode.String` is the entry point and stays at the top level; everything
  # else is grouped so nothing lands in ExDoc's ungrouped catch-all.
  defp groups_for_modules do
    [
      Segmentation: [
        Unicode.String.Break,
        Unicode.String.Break.Tailoring,
        Unicode.String.Segment
      ],
      "Dictionary Segmentation": [
        Unicode.String.Dictionary,
        Unicode.String.DictionaryBreak
      ],
      "Case Mapping": [
        Unicode.String.Case.Folding,
        Unicode.String.Case.Mapping,
        Unicode.String.Case.Mapping.Greek
      ],
      "ICU Backend": [
        Unicode.String.Nif
      ],
      "Break Engines": [
        Unicode.String.Dfa,
        Unicode.String.Dfa.Builder,
        Unicode.String.Dfa.Grapheme,
        Unicode.String.Dfa.Line,
        Unicode.String.Dfa.Sentence,
        Unicode.String.Dfa.Word
      ],
      Internals: [
        Unicode.String.ExtendedPictographic
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "src", "test"]
  defp elixirc_paths(:dev), do: ["lib", "mix", "src", "bench"]
  defp elixirc_paths(_), do: ["lib", "src"]
end
