defmodule Unicode.String.Dfa.Sentence do
  @moduledoc """
  Table-driven engine implementing UAX #29 sentence breaking, with CLDR's
  locale tailoring and abbreviation suppressions.

  Generated from the `SentenceBreak` state machine tables published in PRI #555.
  See `Unicode.String.Dfa` for the engine, `Unicode.String.Break.Tailoring` for
  the tailoring and suppressions, and `Unicode.String.Break.Sentence` for the
  direct-coded implementation retained as a cross-check.

  The arity-1 functions implement UAX #29 as published. The arity-3 and arity-4
  functions add the locale-dependent behaviour on top.
  """

  use Unicode.String.Dfa, type: "SentenceBreak"

  alias Unicode.String.Break.Tailoring

  # The generated `next/1`, `split/1` and `break?/2` implement UAX #29 as
  # published. CLDR adds two locale-dependent behaviours on top, and the
  # arity-3 and arity-4 functions below layer them on:
  #
  #   * a sentence break class extension, applied by rewriting the tailored
  #     characters before the machine sees them (see
  #     `Unicode.String.Break.Tailoring.tailor/3`), and
  #
  #   * abbreviation suppressions, applied by cancelling a break the machine has
  #     already decided on and continuing the sentence.
  #
  # The rewrite preserves UTF-8 byte lengths, so every offset the machine reports
  # over the tailored text indexes the original, and sentences are sliced from
  # the original rather than the rewritten copy.
  #
  # The rewrite is applied once per call rather than once per sentence. Rewriting
  # the remainder at every boundary would make splitting quadratic in the length
  # of the input, which would fall hardest on the locales that have a tailoring.

  @doc "Returns `{sentence, rest}`, or `nil` when `string` is empty."
  def next("", _locale, _suppressions), do: nil

  def next(string, locale, suppressions) do
    length =
      string
      |> Tailoring.tailor(locale, :sentence)
      |> sentence_length(string, 0, 0, locale, suppressions)

    {binary_part(string, 0, length), binary_part(string, length, byte_size(string) - length)}
  end

  @doc "Splits `string` into sentences under `locale`."
  def split("", _locale, _suppressions), do: []

  def split(string, locale, suppressions) do
    string |> splitter(locale, suppressions) |> Enum.to_list()
  end

  @doc """
  Lazily splits `string` into sentences under `locale`.

  The stream carries the tailored text alongside the original and the offset
  reached in it, so the tailoring is applied once at construction and every
  sentence is still sliced from the original string.
  """
  def splitter(string, locale, suppressions) do
    Stream.unfold(
      {Tailoring.tailor(string, locale, :sentence), string, 0},
      &next_tailored(&1, locale, suppressions)
    )
  end

  defp next_tailored({"", _original, _offset}, _locale, _suppressions), do: nil

  defp next_tailored({tailored, original, offset}, locale, suppressions) do
    length = sentence_length(tailored, original, offset, 0, locale, suppressions)
    rest = binary_part(tailored, length, byte_size(tailored) - length)
    {binary_part(original, offset, length), {rest, original, offset + length}}
  end

  # SB11 breaks after "Mr."; the locale's suppression set cancels that break, so
  # the sentence continues into what the rules made the following segment.
  # `offset` locates the sentence in `original`, `taken` is its length so far.
  defp sentence_length(tailored, original, offset, taken, locale, suppressions) do
    {segment, rest} = next(tailored)
    taken = taken + byte_size(segment)

    if rest != "" and
         Tailoring.suppressed?(binary_part(original, offset, taken), locale, suppressions) do
      sentence_length(rest, original, offset, taken, locale, suppressions)
    else
      taken
    end
  end

  @doc "Returns `true` when a sentence boundary falls between the two strings."
  def break?("", _string_after, _locale, _suppressions), do: true
  def break?(_string_before, "", _locale, _suppressions), do: true

  def break?(string_before, string_after, locale, suppressions) do
    combined = string_before <> string_after
    target = byte_size(string_before)

    combined
    |> Tailoring.tailor(locale, :sentence)
    |> boundary_at?(combined, 0, target, locale, suppressions)
  end

  defp boundary_at?(_tailored, _original, offset, target, _locale, _suppressions)
       when offset == target,
       do: true

  defp boundary_at?(tailored, original, offset, target, locale, suppressions) do
    length = sentence_length(tailored, original, offset, 0, locale, suppressions)
    rest = binary_part(tailored, length, byte_size(tailored) - length)

    cond do
      offset + length == target -> true
      offset + length > target -> false
      true -> boundary_at?(rest, original, offset + length, target, locale, suppressions)
    end
  end
end
