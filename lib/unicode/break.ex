defmodule Unicode.String.Break do
  @moduledoc false

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

  @doc """



  """
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

  @doc """



  """
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

  defp split({:break, {_string_before, ["", ""]}}, _rules, [head | rest]) do
    Enum.reverse([head | rest])
  end

  defp split({:break, {_string_before, [fore, ""]}}, _rules, [head | rest]) do
    Enum.reverse([fore | [head | rest]])
  end

  defp split({:break, {_string_before, [fore, aft]}}, rules, ["" | rest]) do
    {fore, aft}
    |> Segment.evaluate_rules(rules)
    |> split(rules, [fore | rest])
  end

  defp split({:break, {_string_before, [fore, aft]}}, rules, [head | rest]) do
    {head <> fore, aft}
    |> Segment.evaluate_rules(rules)
    |> split(rules, [fore | [head | rest]])
  end

  defp split({:no_break, {_string_before, [fore, aft]}}, rules, [head | rest]) do
    {head <> fore, aft}
    |> Segment.evaluate_rules(rules)
    |> split(rules, [head <> fore | rest])
  end

  @doc """



  """
  def next("", _locale, _break, _options) do
    nil
  end

  def next(string, locale, break, options) when break in @break_keys and is_binary(string) do
    << char :: utf8, rest :: binary>> = string

    case next_at({<< char :: utf8 >>, rest}, locale, Map.fetch!(@break_map, break), options) do
      {fore, [match, rest]} ->
        {<< char :: utf8 >> <> fore, match <> rest}
      {fore, rest} ->
        {<< char :: utf8 >> <> fore, rest}
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
    |> next(rules, "")
  end

  defp next({:break, {_string_before, ["", ""]}}, _rules, acc) do
    {acc, ""}
  end

  defp next({:break, {_string_before, [fore, ""]}}, _rules, acc) do
    {acc, fore}
  end

  defp next({:break, {_string_before, rest}}, _rules, acc) do
    {acc, rest}
  end

  defp next({:no_break, {_string_before, [fore, aft]}}, rules, acc) do
    {acc <> fore, aft}
    |> Segment.evaluate_rules(rules)
    |> next(rules, acc <> fore)
  end

  # Recompile this module if any of the segment
  # files change.

  for {_locale, file} <- Segment.locale_map do
    @external_resource Path.join(Segment.segments_dir(), file)
  end

  for locale <- Unicode.String.Segment.locales do
    {:ok, segments} = Unicode.String.Segment.segments(locale)

    for segment_type <- Map.keys(segments) do
      def rules(unquote(locale), unquote(segment_type)) do
        unquote(Macro.escape(Unicode.String.Segment.rules(locale, segment_type)))
      end

      for suppression <- Unicode.String.Segment.suppressions!(locale, segment_type) do
        def suppress(<< unquote(suppression), rest :: binary >>, unquote(locale), unquote(segment_type)) do
          [unquote(suppression), rest]
        end
      end
    end
  end

  @default_locale "root"

  def rules(_other, segment_type) do
    Unicode.String.Segment.rules(@default_locale, segment_type)
  end

  def rules(locale, segment_type, true) do
    suppression_rule = {0.0, {:no_break, locale, segment_type}}

    with {:ok, rules} <- rules(locale, segment_type) do
      {:ok, [suppression_rule | rules]}
    end
  end

  def rules(locale, segment_type, false) do
    rules(locale, segment_type)
  end

  def suppress(string, _other, _segment_type) do
    string
  end

end