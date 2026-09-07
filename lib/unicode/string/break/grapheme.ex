defmodule Unicode.String.Break.Grapheme do
  @moduledoc """
  Direct-coded rule engine implementing UAX #29 grapheme cluster
  segmentation.

  The rules are compiled into ordered guards and function clauses, not into
  regular expressions and not into a transition table.

  The state carried between characters is intentionally small:

  * `prev` — the Grapheme_Cluster_Break property of the previous codepoint
  * `ri_parity` — `:even` or `:odd`, tracking the parity of the run of
    Regional_Indicators ending at `prev` (used by GB12/GB13)
  * `ext_pict_zwj` — `true` when the prefix ends with
    `\\p{Extended_Pictographic} \\p{Extend}* \\p{ZWJ}` (used by GB11)
  * `incb` — `:none | :linker`, tracking progress through the GB9c
    sequence
    `[\\p{InCB=Extend}\\p{InCB=Linker}]* \\p{InCB=Linker}
     [\\p{InCB=Extend}\\p{InCB=Linker}]* × \\p{InCB=Consonant}`.
    Unicode 18 removed the leading `\\p{InCB=Consonant}` that this rule
    previously required.

  Each character is classified once via `Unicode.GraphemeClusterBreak`,
  `Unicode.IndicConjunctBreak` and a compile-time set of
  Extended_Pictographic ranges, then a constant-time decision determines
  whether to emit a break or continue the cluster.
  """

  alias Unicode.GraphemeClusterBreak
  alias Unicode.IndicConjunctBreak

  import Unicode.String.ExtendedPictographic, only: [is_extended_pictographic: 1]

  @doc """
  Returns the index of the next grapheme cluster boundary after position 0
  in `string`, expressed as a `{first_grapheme, rest}` tuple.

  Returns `nil` for the empty string.
  """
  @spec next(String.t()) :: {String.t(), String.t()} | nil
  def next("") do
    nil
  end

  # Two printable ASCII bytes in a row means the first is a complete grapheme
  # cluster, and it can be decided without decoding either codepoint or
  # consulting any property table. Every codepoint in 0x20..0x7E has
  # Grapheme_Cluster_Break=Other, none is Extended_Pictographic and none carries
  # an Indic_Conjunct_Break value, so no rule joins such a pair and GB999
  # applies. In Latin text this is the overwhelmingly common case, and it costs
  # two byte comparisons against the roughly two hundred a full classification
  # of both codepoints would need. Both returned binaries are sub-binaries of
  # the input, so nothing is copied.
  #
  # The precondition is asserted against the Unicode data at compile time,
  # immediately below, so it cannot be invalidated silently.
  @printable_ascii 0x20..0x7E

  for codepoint <- @printable_ascii do
    if GraphemeClusterBreak.grapheme_break(codepoint) != :other do
      raise "U+#{Integer.to_string(codepoint, 16)} is no longer " <>
              "Grapheme_Cluster_Break=Other; the ASCII fast path in #{__MODULE__} " <>
              "is no longer valid."
    end
  end

  def next(<<first, second, _rest::binary>> = string)
      when first in @printable_ascii and second in @printable_ascii do
    {binary_part(string, 0, 1), binary_part(string, 1, byte_size(string) - 1)}
  end

  def next(<<cp::utf8, rest::binary>> = string) do
    state = initial_state(cp, is_extended_pictographic(cp))
    do_next(rest, state, byte_size_utf8(cp), string)
  end

  @doc """
  Splits `string` into a list of grapheme clusters according to UAX #29.
  """
  @spec split(String.t()) :: [String.t()]
  def split(""), do: []

  def split(string) do
    {first, rest} = next(string)
    [first | split(rest)]
  end

  @doc """
  Returns `true` if there is a grapheme cluster boundary between
  `string_before` and `string_after`.

  When `string_before` is empty there is always a boundary (GB1).
  When `string_after` is empty there is always a boundary (GB2).
  """
  @spec break?(String.t(), String.t()) :: boolean
  def break?("", _string_after), do: true
  def break?(_string_before, ""), do: true

  def break?(string_before, <<next_cp::utf8, _::binary>>) do
    state = trailing_state(string_before)
    {operator, _} = decide(state, next_cp)
    operator == :break
  end

  ## Internal

  # Walk forward from offset, deciding at each codepoint whether to break.
  # `taken` is the byte length of the cluster accumulated so far.
  defp do_next("", _state, taken, string) do
    {binary_part(string, 0, taken), ""}
  end

  defp do_next(<<cp::utf8, rest::binary>> = remainder, state, taken, string) do
    case decide(state, cp) do
      {:break, _state} ->
        {binary_part(string, 0, taken), remainder}

      {:no_break, new_state} ->
        do_next(rest, new_state, taken + byte_size_utf8(cp), string)
    end
  end

  # The decision function: given current state and the next codepoint,
  # return {:break | :no_break, new_state}.
  # Below the lowest Extended_Pictographic codepoint no character is
  # pictographic, and none carries an Indic_Conjunct_Break value other than
  # `:none`, so both property lookups and the guard can be skipped entirely.
  # That covers all of ASCII and most of Latin-1, which is the bulk of ordinary
  # Western text. The boundary and the break values are taken from the Unicode
  # data at compile time rather than written out here, and the assumption about
  # Indic_Conjunct_Break is asserted below, so a Unicode update cannot silently
  # invalidate this.
  @latin1_limit Map.fetch!(Unicode.Emoji.emoji(), :extended_pictographic)
                |> Enum.map(&elem(&1, 0))
                |> Enum.min()

  for codepoint <- 0..(@latin1_limit - 1) do
    if IndicConjunctBreak.indic_conjunct_break(codepoint) != :none do
      raise "Indic_Conjunct_Break is no longer :none for all codepoints below " <>
              "U+#{Integer.to_string(@latin1_limit, 16)}; the grapheme break fast path " <>
              "in #{__MODULE__} is no longer valid."
    end
  end

  @latin1_breaks 0..(@latin1_limit - 1)
                 |> Enum.map(&GraphemeClusterBreak.grapheme_break/1)
                 |> List.to_tuple()

  defp decide(state, cp) when cp < @latin1_limit do
    curr = elem(@latin1_breaks, cp)

    {decide_op(state, curr, :none, false, cp), advance(state, curr, :none, false, cp)}
  end

  defp decide(state, cp) do
    curr = GraphemeClusterBreak.grapheme_break(cp)
    incb = IndicConjunctBreak.indic_conjunct_break(cp)
    extpict = is_extended_pictographic(cp)

    operator = decide_op(state, curr, incb, extpict, cp)
    new_state = advance(state, curr, incb, extpict, cp)
    {operator, new_state}
  end

  # GB3: CR × LF
  defp decide_op({:cr, _, _, _}, :lf, _, _, _), do: :no_break
  # GB4: (Control | CR | LF) ÷
  defp decide_op({prev, _, _, _}, _, _, _, _) when prev in [:cr, :lf, :control],
    do: :break

  # GB5: ÷ (Control | CR | LF)
  defp decide_op(_, curr, _, _, _) when curr in [:cr, :lf, :control], do: :break

  # GB6: L × (L | V | LV | LVT)
  defp decide_op({:l, _, _, _}, curr, _, _, _) when curr in [:l, :v, :lv, :lvt],
    do: :no_break

  # GB7: (LV | V) × (V | T)
  defp decide_op({prev, _, _, _}, curr, _, _, _)
       when prev in [:lv, :v] and curr in [:v, :t],
       do: :no_break

  # GB8: (LVT | T) × T
  defp decide_op({prev, _, _, _}, :t, _, _, _) when prev in [:lvt, :t],
    do: :no_break

  # GB9: × (Extend | ZWJ)
  defp decide_op(_, curr, _, _, _) when curr in [:extend, :zwj], do: :no_break

  # GB9a: × SpacingMark
  defp decide_op(_, :spacingmark, _, _, _), do: :no_break

  # GB9b: Prepend ×
  defp decide_op({:prepend, _, _, _}, _, _, _, _), do: :no_break

  # GB9c: [Extend|Linker]* Linker [Extend|Linker]* × \p{InCB=Consonant}
  defp decide_op({_, _, _, :linker}, _, :consonant, _, _), do: :no_break

  # GB11: ExtPict Extend* ZWJ × ExtPict
  defp decide_op({_, _, true, _}, _, _, true, _), do: :no_break

  # GB12 / GB13: RI × RI when the run of preceding RIs has odd parity
  defp decide_op({:regional_indicator, :odd, _, _}, :regional_indicator, _, _, _),
    do: :no_break

  # GB999: Any ÷ Any
  defp decide_op(_state, _curr, _incb, _ext, _cp), do: :break

  # ----- state advance ----------------------------------------------------

  # initial_state builds the state vector from the very first codepoint.
  defp initial_state(cp, extpict?) do
    prev = GraphemeClusterBreak.grapheme_break(cp)
    incb = IndicConjunctBreak.indic_conjunct_break(cp)

    ri_parity =
      if prev == :regional_indicator, do: :odd, else: :even

    # If this codepoint is itself ExtPict (and not ZWJ), open the
    # GB11 sequence; the ZWJ will move us to `true`.
    ext_pict_zwj =
      if extpict? and prev != :zwj, do: :pending, else: false

    incb_state =
      case incb do
        :linker -> :linker
        _ -> :none
      end

    {prev, ri_parity, ext_pict_zwj, incb_state}
  end

  # Compute the state for the codepoint immediately preceding the
  # `string_before` boundary, by walking the string forward. Used only
  # by break?/2.
  defp trailing_state(string_before) do
    [first | rest] = String.to_charlist(string_before)
    state = initial_state(first, is_extended_pictographic(first))

    Enum.reduce(rest, state, fn cp, st ->
      curr = GraphemeClusterBreak.grapheme_break(cp)
      incb = IndicConjunctBreak.indic_conjunct_break(cp)
      extpict = is_extended_pictographic(cp)
      advance(st, curr, incb, extpict, cp)
    end)
  end

  # advance: produce the next state given the current state, the new
  # codepoint's classifications, and the codepoint itself.
  defp advance({_prev, ri_parity, ext_pict_zwj, incb_state}, curr, incb, extpict, _cp) do
    {curr, next_ri_parity(curr, ri_parity), next_ext_pict_zwj(ext_pict_zwj, curr, extpict),
     next_incb_state(incb_state, incb)}
  end

  # Regional-indicator runs toggle odd/even parity (GB12/GB13); any other
  # class resets the run.
  defp next_ri_parity(:regional_indicator, :odd), do: :even
  defp next_ri_parity(:regional_indicator, :even), do: :odd
  defp next_ri_parity(_curr, _ri_parity), do: :even

  # Track the ExtPict-Extend*-ZWJ sequence used by GB11.
  #   ExtPict (not ZWJ)  → :pending (start / restart a sequence)
  #   Extend while pending → :pending (keep it alive)
  #   ZWJ while pending    → true (ready to consume an ExtPict)
  #   anything else        → false
  defp next_ext_pict_zwj(_ext_pict_zwj, curr, true) when curr != :zwj, do: :pending
  defp next_ext_pict_zwj(:pending, :extend, _extpict), do: :pending
  defp next_ext_pict_zwj(:pending, :zwj, _extpict), do: true
  defp next_ext_pict_zwj(_ext_pict_zwj, _curr, _extpict), do: false

  # GB9c InCB tracking.
  #
  # Unicode 18 dropped the leading \p{InCB=Consonant} that Unicode 17
  # required, so a Linker opens the sequence from any state - including the
  # start of text. Anything other than a Linker or an InCB=Extend closes it.
  #
  #   any → :linker on Linker
  #   :linker → :linker on InCB=Extend (which includes ZWJ)
  #   anything else → :none
  defp next_incb_state(_state, :linker), do: :linker
  defp next_incb_state(:linker, :extend), do: :linker
  defp next_incb_state(_state, _), do: :none

  # ----- helpers ----------------------------------------------------------

  defp byte_size_utf8(cp) when cp < 0x80, do: 1
  defp byte_size_utf8(cp) when cp < 0x800, do: 2
  defp byte_size_utf8(cp) when cp < 0x10000, do: 3
  defp byte_size_utf8(_cp), do: 4
end
