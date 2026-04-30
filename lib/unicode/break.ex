defmodule Unicode.String.Break do
  @moduledoc """
  Implements the Unicode break algorithms for graphemes, words,
  sentences and line-breaks.

  This module is a thin dispatcher: it inspects the requested break
  type and locale, delegates dictionary-based word segmentation to
  `Unicode.String.Dictionary` / `Unicode.String.DictionaryBreak`, and
  routes everything else to the single-pass DFA evaluators in
  `Unicode.String.Break.Grapheme`, `…Word`, `…Sentence`, and `…Line`.
  """

  alias Unicode.String.Segment
  alias Unicode.String.Dictionary
  alias Unicode.String.DictionaryBreak
  alias Unicode.String.Break.Grapheme, as: G
  alias Unicode.String.Break.Word, as: W
  alias Unicode.String.Break.Sentence, as: S
  alias Unicode.String.Break.Line, as: L

  @dictionary_locales Dictionary.known_dictionary_locales()

  @break_map %{
    grapheme: :grapheme_cluster_break,
    word: :word_break,
    sentence: :sentence_break,
    line: :line_break,
    graphemes: :grapheme_cluster_break,
    grapheme_cluster: :grapheme_cluster_break,
    words: :word_break,
    sentences: :sentence_break,
    lines: :line_break
  }

  @break_keys Map.keys(@break_map)

  # Southeast Asian scripts use the lookahead-based dictionary
  # break algorithm for script-specific ranges.
  @lookahead_dictionary_locales [:th, :lo, :km, :my]

  ## ----------------------------------------------------------------------
  ## Public API: break? / break / split / next
  ## ----------------------------------------------------------------------

  @doc false
  def break(string, locale, break, options) when break in @break_keys do
    break_at(string, locale, Map.fetch!(@break_map, break), options)
  end

  @doc false
  def break_at("", _locale, _segment_type, _options) do
    {:no_break, {"", {"", ""}}}
  end

  def break_at({"", string_after}, _locale, _segment_type, _options) do
    {:break, {"", {"", string_after}}}
  end

  def break_at(string, locale, segment_type, options) when is_binary(string) do
    break_at({"", string}, locale, segment_type, options)
  end

  def break_at({string_before, string_after}, locale, segment_type, options) do
    op =
      case segment_type do
        :grapheme_cluster_break ->
          if G.break?(string_before, string_after), do: :break, else: :no_break

        :word_break ->
          if W.break?(string_before, string_after), do: :break, else: :no_break

        :sentence_break ->
          suppressions = sentence_suppressions(locale, options)

          if S.break?(string_before, string_after, locale, suppressions),
            do: :break,
            else: :no_break

        :line_break ->
          if L.break?(string_before, string_after), do: :break, else: :no_break
      end

    case {op, string_after} do
      {_, ""} ->
        {op, {string_before, {"", ""}}}

      {_, _} ->
        <<char::utf8, rest::binary>> = string_after
        {op, {string_before, {<<char::utf8>>, rest}}}
    end
  end

  ## ---- split / next dispatch -------------------------------------------

  @doc false
  def split(string, locale, :word = break, options) when locale in @lookahead_dictionary_locales do
    Dictionary.ensure_dictionary_loaded_if_available(locale)

    DictionaryBreak.split_with_fallback(string, locale, fn non_dict_segment ->
      split_segment(non_dict_segment, locale, break, options)
    end)
  end

  def split(string, locale, :line = break, options) when break in @break_keys do
    string
    |> rule_based_line_split(locale, options)
    |> Enum.flat_map(&dict_subsplit_line/1)
  end

  def split(string, locale, break, options) when break in @break_keys do
    case next(string, locale, break, options) do
      {fore, aft} -> [fore | split(aft, locale, break, options)]
      nil -> []
    end
  end

  # Standard rule-based line-break split (the path used before the
  # dictionary post-pass was added).
  defp rule_based_line_split(string, locale, options) do
    case next(string, locale, :line, options) do
      {fore, aft} -> [fore | rule_based_line_split(aft, locale, options)]
      nil -> []
    end
  end

  # Scripts whose runs need dictionary-based line break.
  @dict_line_scripts [
    {:th, 0x0E01..0x0E5B},
    {:lo, 0x0E81..0x0EDF},
    {:my, 0x1000..0x109F},
    {:km, 0x1780..0x17FF}
  ]

  # If a rule-based segment contains a contiguous run of chars in one
  # of the dictionary scripts, replace that run with its dictionary
  # word breaks (keeping any surrounding non-dict prefix attached to
  # the first dict word and any non-dict suffix attached to the last).
  # Minimum codepoints in a contiguous dict-script run before we attempt
  # dictionary-based line break on it. Mirrors DictionaryBreak.@min_word_span.
  @min_dict_run 4

  defp dict_subsplit_line(segment) do
    case detect_dict_script(segment) do
      nil ->
        [segment]

      {locale, _range} ->
        Dictionary.ensure_dictionary_loaded_if_available(locale)

        case DictionaryBreak.split_with_fallback(segment, locale, &[&1]) do
          [] ->
            [segment]

          parts when length(parts) <= 1 ->
            [segment]

          parts ->
            merge_trailing_whitespace(parts)
        end
    end
  end

  # Merge any segment that is purely whitespace into the preceding
  # segment. This matches LB18 ("SP ÷"), where a trailing space attaches
  # to the word it follows. The dictionary fallback tends to emit such
  # whitespace as standalone segments.
  defp merge_trailing_whitespace([]), do: []
  defp merge_trailing_whitespace([head | rest]), do: merge_trailing_whitespace(rest, [head])

  defp merge_trailing_whitespace([], acc), do: Enum.reverse(acc)

  defp merge_trailing_whitespace([next | rest], [prev | acc_rest] = acc) do
    if whitespace_only?(next) and prev != "" do
      merge_trailing_whitespace(rest, [prev <> next | acc_rest])
    else
      merge_trailing_whitespace(rest, [next | acc])
    end
  end

  defp whitespace_only?(""), do: false
  defp whitespace_only?(s), do: String.trim(s) == ""

  # Returns `{locale, range}` of the dictionary script if `segment`
  # contains a run of at least `@min_dict_run` consecutive characters
  # in that script. Otherwise `nil`.
  defp detect_dict_script(segment) do
    Enum.find(@dict_line_scripts, fn {_locale, range} ->
      has_run_in?(segment, range, 0)
    end)
  end

  defp has_run_in?(_, _range, run) when run >= @min_dict_run, do: true
  defp has_run_in?(<<>>, _range, _run), do: false

  defp has_run_in?(<<cp::utf8, rest::binary>>, range, run) do
    if cp in range,
      do: has_run_in?(rest, range, run + 1),
      else: has_run_in?(rest, range, 0)
  end

  defp split_segment(string, locale, break, options) do
    case next(string, locale, break, options) do
      {fore, aft} -> [fore | split_segment(aft, locale, break, options)]
      nil -> []
    end
  end

  @doc false
  def next("", _locale, _break, _options), do: nil

  def next(string, locale, :word = break, options) when locale in @dictionary_locales do
    <<char::utf8, rest::binary>> = string

    case next_dict({<<char::utf8>>, rest}, locale, options) do
      {fore, {_match, rest}} -> {fore, rest}
      {fore, rest} -> {fore, rest}
    end
    |> repeat_if_trimming_required(locale, break, options, options[:trim])
  end

  def next(string, locale, break, options) when break in @break_keys and is_binary(string) do
    pair =
      case Map.fetch!(@break_map, break) do
        :grapheme_cluster_break ->
          G.next(string)

        :word_break ->
          W.next(string)

        :sentence_break ->
          S.next(string, locale, sentence_suppressions(locale, options))

        :line_break ->
          L.next(string)
      end

    pair
    |> repeat_if_trimming_required(locale, break, options, options[:trim])
  end

  defp repeat_if_trimming_required(nil, _locale, _break, _options, _) do
    nil
  end

  defp repeat_if_trimming_required({match, rest}, locale, break, options, true) do
    if Unicode.Property.white_space?(match) do
      next(rest, locale, break, options)
    else
      {match, rest}
    end
  end

  defp repeat_if_trimming_required({match, rest}, _locale, _break, _options, _) do
    {match, rest}
  end

  ## ---- dictionary-driven word splitting (CJK and friends) --------------

  defp next_dict({string_before, ""}, _locale, _options), do: {string_before, ""}

  defp next_dict({string_before, string_after}, locale, options) do
    <<next::utf8, rest::binary>> = string_after
    word = string_before <> <<next::utf8>>

    case Dictionary.find_prefix(word, locale) do
      {:ok, _} ->
        # Found a complete word; absorb any following combining marks.
        {word, rest} = absorb_combining_marks(word, rest)
        next_dict({word, rest}, locale, options)

      :prefix ->
        case next_dict({word, rest}, locale, options) do
          {fore, _aft} when fore == word -> {string_before, string_after}
          other -> other
        end

      :error ->
        {string_before, string_after}
    end
  end

  @combining_categories [:Mn, :Mc, :Me]

  defp absorb_combining_marks(word, <<next::utf8, rest::binary>> = after_word) do
    if Unicode.category(next) in @combining_categories do
      absorb_combining_marks(word <> <<next::utf8>>, rest)
    else
      {word, after_word}
    end
  end

  defp absorb_combining_marks(word, ""), do: {word, ""}

  ## ----------------------------------------------------------------------
  ## Suppressions (sentence break, locale-specific abbreviations)
  ## ----------------------------------------------------------------------

  # Pull the suppression data out at compile time and freeze a MapSet of
  # lower-cased suppression words *without* the trailing period.
  for locale <- Segment.known_segmentation_locales() do
    {:ok, segments} = Segment.segments(locale)

    for {segment_type, _content} <- segments do
      raw = Segment.suppressions!(locale, segment_type)

      cleaned =
        raw
        |> Enum.map(fn entry ->
          entry
          |> String.replace_trailing(".", "")
          |> String.trim()
          |> String.downcase()
        end)
        |> Enum.reject(&(&1 == ""))

      # Only emit a per-locale clause when the suppression set is
      # non-empty. Empty sets fall through to the catch-all below.
      if cleaned != [] do
        defp suppression_set(unquote(locale), unquote(segment_type)) do
          unquote(Macro.escape(MapSet.new(cleaned)))
        end
      end

      def suppressions(unquote(locale), unquote(segment_type)) do
        unquote(Macro.escape(raw))
      end

      def variables(unquote(locale), unquote(segment_type)) do
        unquote(Macro.escape(get_in(segments, [segment_type, :variables])))
      end
    end
  end

  @empty_set MapSet.new()
  defp suppression_set(_locale, _segment_type), do: @empty_set

  def suppressions(_locale, _segment_type), do: []
  def variables(_locale, _segment_type), do: []

  defp sentence_suppressions(locale, options) do
    if Keyword.get(options, :suppressions, true) do
      suppression_set(locale, :sentence_break)
    else
      MapSet.new()
    end
  end

  ## Recompile this module if any segment file changes (preserved from
  ## the original implementation so locale-specific suppressions stay
  ## fresh).
  for {_locale, file} <- Segment.locale_map() do
    @external_resource Path.join(Segment.segments_dir(), file)
  end
end
