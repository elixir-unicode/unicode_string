defmodule Unicode.String.Break do
  @moduledoc """


  """
  alias Unicode.String.Segment

  def grapheme(string, locale) do
    break_at(string, locale, :grapheme_cluster_break)
  end

  def word(string, locale) do
    break_at(string, locale, :word_break)
  end

  def line(string, locale) do
    break_at(string, locale, :line_break)
  end

  def sentence(string, locale) do
    break_at(string, locale, :sentence_break)
  end

  defp break_at(string, locale, segment_type) do
    if locale in Segment.locales do
      {:ok, rules} = rules(locale, segment_type)

      string
      |> Segment.evaluate_rules(rules)
      |> break(rules, [""])
    else
      {:error, Segment.unknown_locale_error(locale)}
    end
  end

  defp break({_break, [fore, ""]}, _rules, [head | rest]) do
    Enum.reverse([head <> fore | rest])
  end

  defp break({:break, [fore, aft]}, rules, [head | rest]) do
    aft
    |> Segment.evaluate_rules(rules)
    |> break(rules, ["" | [head <> fore | rest]])
  end

  defp break({:no_break, [fore, aft]}, rules, [head | rest]) do
    aft
    |> Segment.evaluate_rules(rules)
    |> break(rules, [head <> fore | rest])
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

  def suppress(string, _other, _segment_type) do
    ["", string]
  end

end