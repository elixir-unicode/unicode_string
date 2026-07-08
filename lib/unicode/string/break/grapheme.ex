defmodule Unicode.String.Break.Grapheme do
  @moduledoc """
  Single-pass DFA-style implementation of UAX #29 grapheme cluster
  segmentation.

  The state carried between characters is intentionally small:

  * `prev` — the Grapheme_Cluster_Break property of the previous codepoint
  * `ri_parity` — `:even` or `:odd`, tracking the parity of the run of
    Regional_Indicators ending at `prev` (used by GB12/GB13)
  * `ext_pict_zwj` — `true` when the prefix ends with
    `\\p{Extended_Pictographic} \\p{Extend}* \\p{ZWJ}` (used by GB11)
  * `incb` — `:none | :consonant | :linker`, tracking progress through
    the GB9c sequence
    `\\p{InCB=Consonant} [\\p{InCB=Extend}\\p{InCB=Linker}]* \\p{InCB=Linker}
     [\\p{InCB=Extend}\\p{InCB=Linker}]* × \\p{InCB=Consonant}`

  Each character is classified once via `Unicode.GraphemeClusterBreak`,
  `Unicode.IndicConjunctBreak` and a compile-time set of
  Extended_Pictographic ranges, then a constant-time decision determines
  whether to emit a break or continue the cluster.
  """

  alias Unicode.GraphemeClusterBreak
  alias Unicode.IndicConjunctBreak

  # Build a guard for Extended_Pictographic from the unicode data so we
  # can test it with a single is_extpict/1 guard rather than a function
  # call.
  ext_pict_ranges = Map.fetch!(Unicode.Emoji.emoji(), :extended_pictographic)

  defguardp is_extpict(codepoint)
            when unquote(
                   Enum.reduce(ext_pict_ranges, false, fn
                     {from, to}, false ->
                       quote do: var!(codepoint) in unquote(from)..unquote(to)

                     {from, to}, acc ->
                       quote do:
                               unquote(acc) or
                                 var!(codepoint) in unquote(from)..unquote(to)
                   end)
                 )

  @doc """
  Returns the index of the next grapheme cluster boundary after position 0
  in `string`, expressed as a `{first_grapheme, rest}` tuple.

  Returns `nil` for the empty string.
  """
  @spec next(String.t()) :: {String.t(), String.t()} | nil
  def next("") do
    nil
  end

  def next(<<cp::utf8, rest::binary>> = string) do
    state = initial_state(cp, is_extpict(cp))
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
  defp decide(state, cp) do
    curr = GraphemeClusterBreak.grapheme_break(cp)
    incb = IndicConjunctBreak.indic_conjunct_break(cp)
    extpict = is_extpict(cp)

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

  # GB9c: …Linker [Extend|Linker]* × \p{InCB=Consonant}
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
        :consonant -> :consonant
        _ -> :none
      end

    {prev, ri_parity, ext_pict_zwj, incb_state}
  end

  # Compute the state for the codepoint immediately preceding the
  # `string_before` boundary, by walking the string forward. Used only
  # by break?/2.
  defp trailing_state(string_before) do
    [first | rest] = String.to_charlist(string_before)
    state = initial_state(first, is_extpict(first))

    Enum.reduce(rest, state, fn cp, st ->
      curr = GraphemeClusterBreak.grapheme_break(cp)
      incb = IndicConjunctBreak.indic_conjunct_break(cp)
      extpict = is_extpict(cp)
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
  #   :none → :consonant on Consonant; otherwise stays :none
  #   :consonant → :consonant on Extend; → :linker on Linker; → reset on Consonant; else :none
  #   :linker → :linker on Extend or Linker; → :consonant on a Consonant boundary (already absorbed); else :none
  defp next_incb_state(_state, :consonant), do: :consonant
  defp next_incb_state(:consonant, :extend), do: :consonant
  defp next_incb_state(:consonant, :linker), do: :linker
  defp next_incb_state(:linker, :extend), do: :linker
  defp next_incb_state(:linker, :linker), do: :linker
  defp next_incb_state(_state, _), do: :none

  # ----- helpers ----------------------------------------------------------

  defp byte_size_utf8(cp) when cp < 0x80, do: 1
  defp byte_size_utf8(cp) when cp < 0x800, do: 2
  defp byte_size_utf8(cp) when cp < 0x10000, do: 3
  defp byte_size_utf8(_cp), do: 4
end
