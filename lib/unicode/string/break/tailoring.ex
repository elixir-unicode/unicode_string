defmodule Unicode.String.Break.Tailoring do
  @moduledoc """
  CLDR's locale tailoring of the segmentation rules.

  UAX #14 and UAX #29 define one set of rules for all languages. CLDR carries
  per-locale departures from them as locale data, and this module applies the
  ones this library supports. Two kinds arise:

  * **Break class tailoring**, where a locale gives a character a different
    break class from the one the UCD assigns it. Greek treats U+003B as a
    sentence terminator; Japanese and Chinese treat conditional Japanese
    starters as ideographs rather than non-starters, the tailoring usually
    called CJK *loose* line breaking.

  * **Abbreviation suppressions**, where a locale lists abbreviations such as
    "Mr." that end in a full stop without ending a sentence.

  Neither is expressible in the rules themselves, so both are applied around a
  break engine rather than inside it, and this module is the single home for
  that behaviour.
  """

  alias Unicode.LineBreak
  alias Unicode.SentenceBreak

  # CLDR gives some locales additional sentence-terminating characters. `el.xml`
  # extends `$STerm` with U+003B SEMICOLON and U+037E GREEK QUESTION MARK, so
  # Greek text like "γδ; Ε" breaks at the semicolon.
  #
  # A table-driven engine resolves a character to a symbol with a table fixed at
  # compile time, so it has nowhere to put a per-locale exception. Rewriting the
  # tailored characters to standard characters of the same class before the
  # machine runs has the same effect. The substitutes are chosen to encode to the
  # same number of UTF-8 bytes as the characters they replace, so every byte
  # offset the machine reports still indexes the original string and segments can
  # be sliced from it untouched.
  @sentence_tailoring %{
    el: [
      # U+003B SEMICOLON -> U+0021 EXCLAMATION MARK, 1 byte each
      {[<<0x003B::utf8>>], <<0x0021::utf8>>},
      # U+037E GREEK QUESTION MARK -> U+0589 ARMENIAN FULL STOP, 2 bytes each
      {[<<0x037E::utf8>>], <<0x0589::utf8>>}
    ]
  }

  # `ja.xml`, `zh.xml` and `zh_Hant.xml` move Line_Break=Conditional_Japanese_Starter
  # out of `$NS` and into `$ID`. Root folds it the other way (`$NS` is `[$NS $CJ]`,
  # which is LB1's `CJ -> NS`), so small kana and the like break as ideographs do
  # rather than as non-starters. This is CJK loose line breaking.
  @conditional_japanese_starters LineBreak.line_breaks()
                                 |> Map.fetch!(:cj)
                                 |> Enum.flat_map(fn {from, to} -> Enum.to_list(from..to) end)

  @cj_by_byte_size Enum.group_by(
                     @conditional_japanese_starters,
                     &byte_size(<<&1::utf8>>),
                     &<<&1::utf8>>
                   )

  # U+4E00 CJK UNIFIED IDEOGRAPH-4E00 and U+20000 CJK UNIFIED IDEOGRAPH-20000 are
  # Line_Break=Ideographic and encode to three and four bytes respectively.
  @line_tailoring_cjk [
    {Map.fetch!(@cj_by_byte_size, 3), <<0x4E00::utf8>>},
    {Map.fetch!(@cj_by_byte_size, 4), <<0x20000::utf8>>}
  ]

  # Locale atoms use the BCP 47 hyphen, so the subtag is `:"zh-Hant"` even though
  # the CLDR segment file is named `zh_Hant.xml`.
  @line_tailoring %{
    ja: @line_tailoring_cjk,
    zh: @line_tailoring_cjk,
    "zh-Hant": @line_tailoring_cjk
  }

  @tailoring %{sentence: @sentence_tailoring, line: @line_tailoring}

  # Classes that may appear between the sentence terminator and the break, per
  # SB9/SB10 (`Close* Sp* ParaSep?`), plus the SB5 transparent classes.
  @tail_classes [:sep, :cr, :lf, :sp, :close, :extend, :format]

  # Classes that make up the abbreviation being matched.
  @word_classes [:upper, :lower, :oletter, :numeric, :extend, :format]

  @doc """
  Returns the sentence break class of a codepoint under a locale's tailoring.

  ### Arguments

  * `locale` is a locale atom such as `:en` or `:el`.

  * `codepoint` is an integer codepoint.

  ### Returns

  * The sentence break class as an atom, such as `:sterm` or `:lower`.

  ### Examples

      iex> Unicode.String.Break.Tailoring.classify(:en, ?;)
      :scontinue

      iex> Unicode.String.Break.Tailoring.classify(:el, ?;)
      :sterm

  """
  def classify(:el, 0x003B), do: :sterm
  def classify(:el, 0x037E), do: :sterm
  def classify(_locale, codepoint), do: SentenceBreak.sentence_break(codepoint)

  @doc """
  Rewrites a locale's tailored characters to standard characters carrying the
  break class the locale gives them.

  A table-driven engine resolves a character to a symbol with a table fixed at
  compile time, so it has nowhere to put a per-locale exception. Rewriting the
  tailored characters to standard characters of the class the locale wants has
  the same effect on every rule.

  Each substitute encodes to the same number of UTF-8 bytes as the character it
  replaces, so every byte offset computed over the returned string indexes the
  original string and segments are sliced from the original rather than from the
  rewritten copy. The rewrite never reaches the caller.

  ### Arguments

  * `string` is the text about to be segmented.

  * `locale` is a locale atom such as `:en`, `:el` or `:ja`.

  * `break_type` is `:sentence`, `:line`, `:word` or `:grapheme`.

  ### Returns

  * `string` unchanged when the locale has no tailoring for this break type,
    which is the overwhelming majority of cases.

  * A string of the same byte length with the tailored characters substituted.

  ### Examples

      iex> Unicode.String.Break.Tailoring.tailor("γδ; Ε", :en, :sentence)
      "γδ; Ε"

      iex> Unicode.String.Break.Tailoring.tailor("γδ; Ε", :el, :sentence)
      "γδ! Ε"

      iex> Unicode.String.Break.Tailoring.tailor("ぁあ", :en, :line)
      "ぁあ"

      iex> Unicode.String.Break.Tailoring.tailor("ぁあ", :ja, :line)
      "一あ"

  """
  def tailor(string, locale, break_type) do
    case @tailoring do
      %{^break_type => %{^locale => substitutions}} ->
        Enum.reduce(substitutions, string, fn {from, to}, accumulator ->
          :binary.replace(accumulator, from, to, [:global])
        end)

      _no_tailoring ->
        string
    end
  end

  @doc """
  Returns `true` when a segment ends in an abbreviation the locale suppresses
  breaking after.

  CLDR lists abbreviations such as "Mr." and "Dr." that end in a full stop
  without ending a sentence. The rules break after them regardless, so the break
  is cancelled afterwards by matching the segment's trailing word against the
  locale's suppression set.

  Only an ATerm-led break can be suppressed. A segment ending in an STerm is a
  sentence end whatever word precedes it, and the check rejects it because the
  character before the trailing `Close* Sp* ParaSep?` run is not an ATerm.

  ### Arguments

  * `segment` is the candidate sentence, ending at the break being tested.

  * `locale` is a locale atom such as `:en` or `:de`.

  * `suppressions` is a `MapSet` of downcased abbreviations, as returned by
    `Unicode.String.Segment.suppressions!/2`.

  ### Returns

  * `true` when the break should be cancelled and the segment extended.

  * `false` otherwise.

  ### Examples

      iex> suppressions = MapSet.new(["mr"])
      iex> Unicode.String.Break.Tailoring.suppressed?("Hello Mr.", :en, suppressions)
      true

      iex> suppressions = MapSet.new(["mr"])
      iex> Unicode.String.Break.Tailoring.suppressed?("Hello Ms.", :en, suppressions)
      false

  """
  def suppressed?(_segment, _locale, suppressions) when suppressions == %MapSet{}, do: false

  def suppressed?(segment, locale, suppressions) do
    case :unicode.characters_to_list(segment) do
      codepoints when is_list(codepoints) ->
        codepoints |> Enum.reverse() |> suppressed_tail?(locale, suppressions)

      _not_valid_utf8 ->
        false
    end
  end

  defp suppressed_tail?(reversed, locale, suppressions) do
    case drop_tail(reversed, locale) do
      [aterm | preceding] ->
        classify(locale, aterm) == :aterm and
          trailing_word_suppressed?(preceding, locale, suppressions)

      [] ->
        false
    end
  end

  defp trailing_word_suppressed?(reversed, locale, suppressions) do
    word =
      reversed
      |> Enum.take_while(&(classify(locale, &1) in @word_classes))
      |> Enum.reverse()
      |> List.to_string()

    word != "" and MapSet.member?(suppressions, String.downcase(word))
  end

  defp drop_tail([], _locale), do: []

  defp drop_tail([codepoint | rest] = all, locale) do
    if classify(locale, codepoint) in @tail_classes do
      drop_tail(rest, locale)
    else
      all
    end
  end
end
