defmodule Unicode.String.Break do
  @moduledoc """
  Implements the Unicode break algorithm for words
  and lines.

  """

  alias Unicode.String.Segment
  alias Unicode.String.Dictionary

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

  @doc false
  def break(string, locale, break, options) when break in @break_keys do
    break_at(string, locale, Map.fetch!(@break_map, break), options)
  end

  @doc false
  def break_at("", _locale, _segment_type, _options) do
    {:no_break, {"", {"", ""}}}
  end

  def break_at(string, locale, segment_type, options) when is_binary(string) do
    break_at({"", string}, locale, segment_type, options)
  end

  def break_at({"", string_after}, _locale, _segment_type, _options) do
    {:break, {"", {"", string_after}}}
  end

  def break_at({string_before, string_after}, locale, segment_type, options) do
    suppress? = Keyword.get(options, :suppressions, true)
    {:ok, rules} = rules(locale, segment_type, suppress?)

    {string_before, string_after}
    |> Segment.evaluate_rules(rules)
  end

  @doc false
  def split(string, locale, break, options) when break in @break_keys do
    case next(string, locale, break, options) do
      {fore, aft} ->
        [fore | split(aft, locale, break, options)]

      nil ->
        []
    end
  end

  @doc false
  def next("", _locale, _break, _options) do
    nil
  end

  def next(string, locale, :word = break, options) when locale in @dictionary_locales do
    <<char::utf8, rest::binary>> = string

    case next_at({<<char::utf8>>, rest}, locale, :word, options) do
      {fore, {_match, rest}} ->
        {fore, rest}

      {fore, rest} ->
        {fore, rest}
    end
    |> repeat_if_trimming_required(locale, break, options, options[:trim])
  end

  def next(string, locale, break, options) when break in @break_keys and is_binary(string) do
    <<char::utf8, rest::binary>> = string

    case next_at({<<char::utf8>>, rest}, locale, Map.fetch!(@break_map, break), options) do
      {fore, {match, rest}} ->
        {<<char::utf8>> <> fore, match <> rest}

      {fore, rest} ->
        {<<char::utf8>> <> fore, rest}
    end
    |> repeat_if_trimming_required(locale, break, options, options[:trim])
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

  defp next_at({string_before, ""}, locale, :word, _options)
      when locale in @dictionary_locales do
    {string_before, ""}
  end

  defp next_at({string_before, string_after}, locale, :word = break, options)
      when locale in @dictionary_locales do
    <<next::utf8, rest::binary>> = string_after
    word = string_before <> <<next::utf8>>

    case Dictionary.find_prefix(word, locale) do
      {:ok, _} ->
        next_at({word, rest}, locale, break, options)
      :prefix ->
        # If its a prefix then we keep going to see if we have a word
        # But if the next step doesn't produce either a prefix or
        # a word then it should be a break here
        case next_at({word, rest}, locale, break, options) do
          {fore, _aft} when fore == word ->
            {string_before, string_after}
          other ->
            other
        end
      :error ->
        {string_before, string_after}
    end
  end

  defp next_at({string_before, string_after}, locale, segment_type, options) do
    suppress? = Keyword.get(options, :suppressions, true)
    {:ok, rules} = rules(locale, segment_type, suppress?)

    {string_before, string_after}
    |> Segment.evaluate_rules(rules)
    |> do_next(rules, "")
  end

  defp do_next({:break, {_string_before, {"", ""}}}, _rules, acc) do
    {acc, ""}
  end

  defp do_next({:break, {_string_before, {fore, ""}}}, _rules, acc) do
    {acc, fore}
  end

  defp do_next({:break, {_string_before, rest}}, _rules, acc) do
    {acc, rest}
  end

  defp do_next({:no_break, {_string_before, {fore, ""}}}, _rules, acc) do
    {acc <> fore, ""}
  end

  # Previously we were doing {acc <> fore, aft} but more context
  # is needed for some rules so now its {string_before <> fore, aft}

  defp do_next({:no_break, {string_before, {fore, aft}}}, rules, acc) do
    {string_before <> fore, aft}
    |> Segment.evaluate_rules(rules)
    |> do_next(rules, acc <> fore)
  end

  # Recompile this module if any of the segment
  # files change.

  for {_locale, file} <- Segment.locale_map() do
    @external_resource Path.join(Segment.segments_dir(), file)
  end

  @suppression_rules %{
    sentence_break: %{id: 10.5, value: "$Sp+ $Suppressions $Close* $Sp* ($ParaSep?) ×"}
  }

  # Returns a list of rules applicable for
  # a given locale and segment type.
  defp rules(locale, segment_type)

  # Returns the variable definitions for
  # a given locale and segment type.
  @doc false
  def variables(locale, segment_type)

  # Returns a list of suppressions
  # (abbreviations) that can be used
  # to suppress an otherwise acceptable
  # break point.

  # Examples
  #
  #     => Unicode.String.Break.variables "en", :sentence_break
  #     [
  #       %{name: "$CR", value: "\\p{Sentence_Break=CR}"},
  #       %{name: "$LF", value: "\\p{Sentence_Break=LF}"},
  #       %{name: "$Extend", value: "\\p{Sentence_Break=Extend}"},
  #       %{name: "$Format", value: "\\p{Sentence_Break=Format}"},
  #       %{name: "$Sep", value: "\\p{Sentence_Break=Sep}"},
  #       %{name: "$Sp", value: "\\p{Sentence_Break=Sp}"},
  #       %{name: "$Lower", value: "\\p{Sentence_Break=Lower}"},
  #       ...
  #     ]
  @doc false
  def suppressions(locale, segment_type)

  @doc false
  def suppressions_rule(locale, segment_type)

  for locale <- Segment.known_segmentation_locales() do
    {:ok, segments} = Segment.segments(locale)

    for segment_type <- Map.keys(segments) do
      defp rules(unquote(locale), unquote(segment_type)) do
        unquote(Macro.escape(Segment.rules(locale, segment_type)))
      end

      def variables(unquote(locale), unquote(segment_type)) do
        unquote(Macro.escape(get_in(segments, [segment_type, :variables])))
      end

      def suppressions(unquote(locale), unquote(segment_type)) do
        unquote(Macro.escape(Segment.suppressions!(locale, segment_type)))
      end

      suppressions_rule = Map.get(@suppression_rules, segment_type)
      suppressions_variable = Segment.suppressions_variable(locale, segment_type)

      if suppressions_rule && suppressions_variable do
        variables =
          get_in(segments, [segment_type, :variables])
          |> Segment.expand_variables([suppressions_variable])

        rule = Segment.compile_rule(suppressions_rule, variables, [:caseless])

        def suppressions_rule(unquote(locale), unquote(segment_type)) do
          unquote(Macro.escape(rule))
        end
      end
    end
  end

  @default_locale :root

  defp rules(_other, segment_type) do
    rules(@default_locale, segment_type)
  end

  def suppressions_rule(_locale, _segment_type) do
    nil
  end

  @doc false
  def rules(locale, break_type, true) do
    if suppressions_rule = suppressions_rule(locale, break_type) do
      {:ok, rules} = rules(locale, break_type)
      {:ok, sort_rules([suppressions_rule | rules])}
    else
      rules(locale, break_type)
    end
  end

  def rules(locale, break_type, _) do
    rules(locale, break_type)
  end

  defp sort_rules(rules) do
    Enum.sort_by(rules, &elem(&1, 0))
  end
end
