defmodule Unicode.String.Break.Word do
  @moduledoc """
  Single-pass DFA-style implementation of UAX #29 word break.

  ## State

  Per-position state is intentionally compact:

  * `prev`, `prev2` — the *effective* Word_Break property of the
    previous and second-previous codepoint, where `Extend`, `Format`,
    and `ZWJ` are skipped over (per WB4). `prev2` is only needed for
    WB7 (`AHLetter MidLetter|MidNumLetQ × AHLetter`),
    WB7c (`HebrewLetter DoubleQuote × HebrewLetter`), and
    WB11 (`Numeric MidNum|MidNumLetQ × Numeric`).

  * `ri_parity` — `:odd` or `:even`, parity of the run of
    Regional_Indicators ending at `prev` (WB15/16).

  * `prev_actual` — the Word_Break property of the codepoint
    *immediately* preceding the current one (without WB4 skipping).
    Required by rules that don't allow transparent characters in
    between, namely WB3 (`CR × LF`), WB3c (`ZWJ × ExtPict`), and
    WB3d (`WSegSpace × WSegSpace`).

  ## Lookahead

  Some rules require knowing the character *after* the candidate
  break (WB6, WB7b, WB12). The walker therefore reads codepoints with
  one codepoint of buffered lookahead and resolves these rules at
  decision time.
  """

  alias Unicode.WordBreak

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

  @ah [:aletter, :hebrew_letter]
  @midnumletq [:midnumlet, :single_quote]
  @transparent [:extend, :format, :zwj]

  @doc """
  Returns `{first_word, rest}` for `string`, or `nil` for the empty string.
  """
  @spec next(String.t()) :: {String.t(), String.t()} | nil
  def next(""), do: nil

  def next(string) do
    {head_len, rest} = next_boundary(string)
    {binary_part(string, 0, head_len), rest}
  end

  @doc """
  Splits `string` into a list of word-break segments.
  """
  @spec split(String.t()) :: [String.t()]
  def split(""), do: []

  def split(string) do
    {head, rest} = next(string)
    [head | split(rest)]
  end

  @doc """
  Boundary predicate: `true` if there is a word boundary between
  `string_before` and `string_after`.
  """
  @spec break?(String.t(), String.t()) :: boolean
  def break?("", _), do: true
  def break?(_, ""), do: true

  def break?(string_before, <<curr_cp::utf8, after_rest::binary>>) do
    state = trailing_state(string_before)
    peek = peek_effective(after_rest)
    decide_op(state, curr_cp, peek) == :break
  end

  ## Walking helpers

  # Returns {byte_length_of_first_segment, remainder_binary}.
  defp next_boundary(<<cp::utf8, rest::binary>> = string) do
    state = initial_state(cp)
    walk(rest, state, byte_size_utf8(cp), string)
  end

  defp walk("", _state, taken, string) do
    {taken, binary_part(string, taken, byte_size(string) - taken)}
  end

  defp walk(<<cp::utf8, rest::binary>>, state, taken, string) do
    peek = peek_effective(rest)

    case decide_op(state, cp, peek) do
      :break ->
        {taken, binary_part(string, taken, byte_size(string) - taken)}

      :no_break ->
        new_state = advance(state, cp)
        walk(rest, new_state, taken + byte_size_utf8(cp), string)
    end
  end

  # Returns the first codepoint that is *not* WB4-transparent, scanning
  # forward and skipping over Extend/Format/ZWJ. Used for the 1-char
  # lookahead in WB6/WB7b/WB12.
  defp peek_effective(""), do: nil

  defp peek_effective(<<cp::utf8, rest::binary>>) do
    case WordBreak.word_break(cp) do
      cls when cls in [:extend, :format, :zwj] -> peek_effective(rest)
      _ -> cp
    end
  end

  ## Decision

  # state = {prev, prev2, ri_parity, prev_actual}

  # The decision: is there a break between the previous codepoint
  # (effectively `prev`) and the current codepoint `curr_cp`?
  #
  # This is a direct, ordered transcription of the UAX #29 word-break rule
  # table (WB3–WB16). Its branch count mirrors the specification; splitting
  # it would obscure the one-to-one correspondence with the rules.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp decide_op({prev, prev2, ri_parity, prev_actual}, curr_cp, peek_cp) do
    curr = WordBreak.word_break(curr_cp)
    extpict? = is_extpict(curr_cp)

    cond do
      # WB3: CR × LF (no transparent characters allowed in between)
      prev_actual == :cr and curr == :lf ->
        :no_break

      # WB3a: (Newline | CR | LF) ÷
      prev_actual in [:newline, :cr, :lf] ->
        :break

      # WB3b: ÷ (Newline | CR | LF)
      curr in [:newline, :cr, :lf] ->
        :break

      # WB3c: ZWJ × Extended_Pictographic
      prev_actual == :zwj and extpict? ->
        :no_break

      # WB3d: WSegSpace × WSegSpace (no transparent characters in between)
      prev_actual == :wsegspace and curr == :wsegspace ->
        :no_break

      # WB4: × (Extend | Format | ZWJ)
      curr in @transparent ->
        :no_break

      # WB5: AHLetter × AHLetter
      prev in @ah and curr in @ah ->
        :no_break

      # WB6: AHLetter × (MidLetter | MidNumLetQ) AHLetter
      prev in @ah and (curr == :midletter or curr in @midnumletq) and
          peek_class(peek_cp) in @ah ->
        :no_break

      # WB7: AHLetter (MidLetter | MidNumLetQ) × AHLetter
      prev2 in @ah and (prev == :midletter or prev in @midnumletq) and curr in @ah ->
        :no_break

      # WB7a: HebrewLetter × Single_Quote
      prev == :hebrew_letter and curr == :single_quote ->
        :no_break

      # WB7b: HebrewLetter × Double_Quote HebrewLetter
      prev == :hebrew_letter and curr == :double_quote and
          peek_class(peek_cp) == :hebrew_letter ->
        :no_break

      # WB7c: HebrewLetter Double_Quote × HebrewLetter
      prev2 == :hebrew_letter and prev == :double_quote and curr == :hebrew_letter ->
        :no_break

      # WB8: Numeric × Numeric
      prev == :numeric and curr == :numeric ->
        :no_break

      # WB9: AHLetter × Numeric
      prev in @ah and curr == :numeric ->
        :no_break

      # WB10: Numeric × AHLetter
      prev == :numeric and curr in @ah ->
        :no_break

      # WB11: Numeric (MidNum | MidNumLetQ) × Numeric
      prev2 == :numeric and (prev == :midnum or prev in @midnumletq) and curr == :numeric ->
        :no_break

      # WB12: Numeric × (MidNum | MidNumLetQ) Numeric
      prev == :numeric and (curr == :midnum or curr in @midnumletq) and
          peek_class(peek_cp) == :numeric ->
        :no_break

      # WB13: Katakana × Katakana
      prev == :katakana and curr == :katakana ->
        :no_break

      # WB13a: (AHLetter | Numeric | Katakana | ExtendNumLet) × ExtendNumLet
      prev in [:aletter, :hebrew_letter, :numeric, :katakana, :extendnumlet] and
          curr == :extendnumlet ->
        :no_break

      # WB13b: ExtendNumLet × (AHLetter | Numeric | Katakana)
      prev == :extendnumlet and curr in [:aletter, :hebrew_letter, :numeric, :katakana] ->
        :no_break

      # WB15/16: Regional_Indicator pair (odd parity ⇒ pair × pair)
      prev == :regional_indicator and curr == :regional_indicator and ri_parity == :odd ->
        :no_break

      # WB999: Any ÷ Any
      true ->
        :break
    end
  end

  defp peek_class(nil), do: nil
  # For lookahead, WB4 says we should look past Extend/Format/ZWJ as well.
  # For our purposes, only WB6/WB7b/WB12 use peek; their target classes
  # (AHLetter / HebrewLetter / Numeric) are never transparent, so we
  # don't have to skip — but if the next char IS transparent we should
  # treat it as "not the relevant class".
  defp peek_class(cp), do: WordBreak.word_break(cp)

  ## State management

  defp initial_state(cp) do
    cls = WordBreak.word_break(cp)
    ri_parity = if cls == :regional_indicator, do: :odd, else: :even

    {effective_prev, effective_prev2} =
      if cls in @transparent, do: {:other, :other}, else: {cls, :other}

    {effective_prev, effective_prev2, ri_parity, cls}
  end

  defp advance({prev, prev2, ri_parity, _prev_actual}, cp) do
    cls = WordBreak.word_break(cp)

    if cls in @transparent do
      # WB4: transparent; effective prev/prev2 unchanged. RI parity is also unchanged.
      # We still record the actual class so WB3-WB3d can see it.
      {prev, prev2, ri_parity, cls}
    else
      {cls, prev, next_ri_parity(cls, ri_parity), cls}
    end
  end

  # Regional-indicator runs toggle odd/even parity (WB15/WB16); any other
  # class resets the run.
  defp next_ri_parity(:regional_indicator, :odd), do: :even
  defp next_ri_parity(:regional_indicator, :even), do: :odd
  defp next_ri_parity(_cls, _ri_parity), do: :even

  defp trailing_state(string_before) do
    [first | rest] = String.to_charlist(string_before)
    state = initial_state(first)
    Enum.reduce(rest, state, fn cp, st -> advance(st, cp) end)
  end

  ## utility

  defp byte_size_utf8(cp) when cp < 0x80, do: 1
  defp byte_size_utf8(cp) when cp < 0x800, do: 2
  defp byte_size_utf8(cp) when cp < 0x10000, do: 3
  defp byte_size_utf8(_cp), do: 4
end
