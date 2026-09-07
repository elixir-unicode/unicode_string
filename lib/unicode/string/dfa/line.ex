defmodule Unicode.String.Dfa.Line do
  @moduledoc """
  Table-driven engine implementing UAX #14 line breaking, with CLDR's CJK
  locale tailoring.

  Generated from the `LineBreak` state machine tables published in PRI #555. See
  `Unicode.String.Dfa` for the engine, `Unicode.String.Break.Tailoring` for the
  locale tailoring, and `Unicode.String.Break.Line` for the direct-coded
  implementation retained as a cross-check.

  The arity-1 functions implement UAX #14 as published. The arity-2 and arity-3
  functions add the locale tailoring on top.
  """

  use Unicode.String.Dfa, type: "LineBreak", dictionary_pass: true

  alias Unicode.String.Break.Tailoring

  # The generated `next/1`, `split/1` and `break?/2` implement UAX #14 as
  # published. `ja`, `zh` and `zh_Hant` tailor it by moving
  # Line_Break=Conditional_Japanese_Starter out of `$NS` and into `$ID`, so the
  # arity-2 and arity-3 functions below rewrite those characters before the
  # machine sees them. The rewrite preserves UTF-8 byte lengths, so segments are
  # sliced from the original string and the rewrite never reaches the caller.

  @doc "Returns `{segment, rest}`, or `nil` when `string` is empty."
  def next("", _locale), do: nil

  def next(string, locale) do
    {tailored_segment, _rest} = string |> Tailoring.tailor(locale, :line) |> next()
    length = byte_size(tailored_segment)
    {binary_part(string, 0, length), binary_part(string, length, byte_size(string) - length)}
  end

  @doc """
  Splits `string` into line-break segments under `locale`.

  The tailoring is applied once for the whole string rather than once per
  segment, so a tailored locale costs one extra pass over the input rather than
  one per boundary.
  """
  def split("", _locale), do: []

  def split(string, locale), do: string |> splitter(locale) |> Enum.to_list()

  @doc """
  Lazily splits `string` into line-break segments under `locale`.

  The stream carries the tailored text alongside the original and the offset
  reached in it, so the tailoring is applied once at construction and every
  segment is still sliced from the original string.
  """
  def splitter(string, locale) do
    Stream.unfold({Tailoring.tailor(string, locale, :line), string, 0}, &next_tailored/1)
  end

  defp next_tailored({"", _original, _offset}), do: nil

  defp next_tailored({tailored, original, offset}) do
    {segment, rest} = next(tailored)
    length = byte_size(segment)
    {binary_part(original, offset, length), {rest, original, offset + length}}
  end

  @doc "Returns `true` when a line break opportunity falls between the two strings."
  def break?("", _string_after, _locale), do: true
  def break?(_string_before, "", _locale), do: true

  def break?(string_before, string_after, locale) do
    combined = string_before <> string_after

    combined
    |> Tailoring.tailor(locale, :line)
    |> boundary_at?(byte_size(string_before))
  end
end
