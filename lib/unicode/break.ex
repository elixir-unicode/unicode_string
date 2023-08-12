defmodule Unicode.String.Break do
  @moduledoc """
  Implements the Unicode break algorithm

  """

  alias Unicode.String.Segment

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

  defp break_at(string, locale, segment_type, options) when is_binary(string) do
    break_at({"", string}, locale, segment_type, options)
  end

  defp break_at({string_before, string_after}, locale, segment_type, options) do
    suppress? = Keyword.get(options, :suppressions, true)
    {:ok, rules} = rules(locale, segment_type, suppress?)

    {string_before, string_after}
    |> Segment.evaluate_rules(rules)
  end

  @doc false
  def split(string, locale, break, options) when break in @break_keys do
    split_at(string, locale, Map.fetch!(@break_map, break), options)
  end

  defp split_at(string, locale, segment_type, options) when is_binary(string) do
    split_at({"", string}, locale, segment_type, options)
  end

  defp split_at({string_before, string_after}, locale, segment_type, options) do
    suppress? = Keyword.get(options, :suppressions, true)
    {:ok, rules} = rules(locale, segment_type, suppress?)

    {string_before, string_after}
    |> Segment.evaluate_rules(rules)
    |> split(rules, [""])
  end

  defp split({:break, {_string_before, {"", ""}}}, _rules, [head | rest]) do
    Enum.reverse([head | rest])
  end

  defp split({:break, {_string_before, {fore, ""}}}, _rules, [head | rest]) do
    Enum.reverse([fore | [head | rest]])
  end

  defp split({:break, {_string_before, {fore, aft}}}, rules, ["" | rest]) do
    {fore, aft}
    |> Segment.evaluate_rules(rules)
    |> split(rules, [fore | rest])
  end

  defp split({:break, {_string_before, {fore, aft}}}, rules, [head | rest]) do
    {head <> fore, aft}
    |> Segment.evaluate_rules(rules)
    |> split(rules, [fore | [head | rest]])
  end

  defp split({:no_break, {_string_before, {fore, aft}}}, rules, [head | rest]) do
    {head <> fore, aft}
    |> Segment.evaluate_rules(rules)
    |> split(rules, [head <> fore | rest])
  end

  @doc false
  def next("", _locale, _break, _options) do
    nil
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

  defp do_next({:no_break, {_string_before, {fore, aft}}}, rules, acc) do
    {acc <> fore, aft}
    |> Segment.evaluate_rules(rules)
    |> do_next(rules, acc <> fore)
  end

  # Recompile this module if any of the segment
  # files change.

  for {_locale, file} <- Segment.locale_map() do
    @external_resource Path.join(Segment.segments_dir(), file)
  end

  @suppression_rules %{
    sentence_break: %{id: 10.5, value: "$Suppressions $Close* $Sp* $ParaSep? ×"}
  }

  # Returns a list of rules applicable for
  # a given locale and segment type.
  defp rules(locale, segment_type)

  # Returns the variable definitions for
  # a given locale and segment typ.
  defp variables(locale, segment_type)

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
  defp suppressions(locale, segment_type)

  # Returns the suppression rule for a
  # given locale and segment type.
  #
  # Examples
  #
  #     => Unicode.String.Break.suppressions "en", :sentence_break
  #     ["L.P.", "Alt.", "Approx.", "E.G.", "O.", "Maj.", "Misc.", "P.O.", "J.D.",
  #      "Jam.", "Card.", "Dec.", "Sept.", "MR.", "Long.", "Hat.", "G.", "Link.", "DC.",
  #      "D.C.", "M.T.", "Hz.", "Mrs.", "By.", "Act.", "Var.", "N.V.", "Aug.", "B.",
  #      "S.A.", "Up.", "Job.", "Num.", "M.I.T.", "Ok.", "Org.", "Ex.", "Cont.", "U.",
  #      "Mart.", "Fn.", "Abs.", "Lt.", "OK.", "Z.", "E.", "Kb.", "Est.", "A.M.",
  #      "L.A.", ...]

  defp suppressions_rule(locale, segment_type)

  for locale <- Segment.known_segmentation_locales() do
    {:ok, segments} = Segment.segments(locale)

    for segment_type <- Map.keys(segments) do
      defp rules(unquote(locale), unquote(segment_type)) do
        unquote(Macro.escape(Segment.rules(locale, segment_type)))
      end

      defp variables(unquote(locale), unquote(segment_type)) do
        unquote(Macro.escape(get_in(segments, [segment_type, :variables])))
      end

      defp suppressions(unquote(locale), unquote(segment_type)) do
        unquote(Macro.escape(Segment.suppressions!(locale, segment_type)))
      end

      suppressions_rule = Map.get(@suppression_rules, segment_type)
      suppressions_variable = Segment.suppressions_variable(locale, segment_type)

      if suppressions_rule && suppressions_variable do
        variables =
          get_in(segments, [segment_type, :variables])
          |> Segment.expand_variables([suppressions_variable])

        rule = Segment.compile_rule(suppressions_rule, variables)

        defp suppressions_rule(unquote(locale), unquote(segment_type)) do
          unquote(Macro.escape(rule))
        end
      end
    end
  end

  @default_locale "root"

  defp rules(_other, segment_type) do
    Segment.rules(@default_locale, segment_type)
  end

  defp suppressions_rule(_locale, _segment_type) do
    nil
  end

  @doc false
  defp rules(locale, break_type, true) do
    if suppressions_rule = suppressions_rule(locale, break_type) do
      {:ok, rules} = rules(locale, break_type)
      {:ok, [suppressions_rule | rules]}
    else
      rules(locale, break_type)
    end
  end

  defp rules(locale, segment_type, _) do
    rules(locale, segment_type)
  end
end
