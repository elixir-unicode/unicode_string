defmodule Unicode.String.Break.Sentence do
  @moduledoc """
  Single-pass DFA-style implementation of UAX #29 sentence break with
  locale-specific class extensions and abbreviation suppressions.

  ## Background

  The sentence-break algorithm differs from grapheme/word break in two
  important ways:

  * The **default** rule is *no break* (rule SB998 `× Any`). Sentence
    boundaries are emitted only by SB4 (`ParaSep ÷`) and by SB11
    (`SATerm Close* Sp* ParaSep? ÷`), in the absence of an earlier
    suppressing rule.

  * SB8 has unbounded forward look-ahead — at an `ATerm Close* Sp*` it
    suppresses the break if a `Lower` letter is reached before any of
    `OLetter | Upper | Lower | ParaSep | SATerm`.

  ## Locale-specific class extensions

  Some locales extend the standard Sentence_Break property classes.
  CLDR's `el.xml`, for example, extends `$STerm` to include U+003B
  (ASCII semicolon) so that Greek text like "γδ; Ε" breaks at the
  semicolon. The walker accepts a `locale` argument and applies these
  per-locale overrides via `classify/2`.

  ## State

  The walker carries:

  * `prev_actual` — the property of the immediately-previous codepoint
    (without the SB5 transparent skip). Needed for SB3 (`CR × LF`).

  * `effective_prev` — the property of the previous *non-transparent*
    codepoint (Extend/Format are skipped per SB5).

  * `before_aterm` — the effective property *before* the most recent
    `ATerm`, used by SB7 (`(Upper|Lower) ATerm × Upper`).

  * `phase` — encodes how far we are through a potential
    sentence-terminating sequence `(SA)Term Close* Sp* ParaSep?`.

  ## Suppressions

  Locale-specific suppressions (e.g. "Mr.", "Dr.") are applied as a
  post-pass: when SB11 would fire after an ATerm-led sequence, the
  walker compares the trailing fragment of the segment against the
  suppression set and cancels the break on a longest-match.
  """

  alias Unicode.SentenceBreak

  @transparent [:extend, :format]

  @doc """
  Returns `{first_sentence, rest}` for `string`, or `nil` for empty input.
  """
  @spec next(String.t(), atom() | binary(), MapSet.t()) ::
          {String.t(), String.t()} | nil
  def next("", _locale, _suppressions), do: nil

  def next(string, locale, suppressions) do
    {head_len, rest} = next_boundary(string, locale, suppressions)
    {binary_part(string, 0, head_len), rest}
  end

  @doc "Splits `string` into sentences."
  @spec split(String.t(), atom() | binary(), MapSet.t()) :: [String.t()]
  def split("", _locale, _suppressions), do: []

  def split(string, locale, suppressions) do
    {head, rest} = next(string, locale, suppressions)
    [head | split(rest, locale, suppressions)]
  end

  @doc """
  Boundary predicate. Returns `true` if there is a sentence break
  between `string_before` and `string_after`.

  When suppressing, the suppression check matches the trailing word
  of `string_before`.
  """
  @spec break?(String.t(), String.t(), atom() | binary(), MapSet.t()) :: boolean
  def break?("", _, _, _), do: true
  def break?(_, "", _, _), do: true

  def break?(
        string_before,
        <<curr_cp::utf8, rest::binary>> = string_after,
        locale,
        suppressions
      ) do
    {state, segment_offset} = trailing_state_walk(string_before, locale, suppressions)
    full = string_before <> string_after

    case decide(
           state,
           curr_cp,
           rest,
           byte_size(string_before) - segment_offset,
           binary_part(full, segment_offset, byte_size(full) - segment_offset),
           locale,
           suppressions
         ) do
      :break -> true
      {:no_break, _} -> false
    end
  end

  ## Walker

  defp next_boundary(<<cp::utf8, rest::binary>> = string, locale, suppressions) do
    state = initial_state(cp, locale)
    walk(rest, state, byte_size_utf8(cp), string, locale, suppressions)
  end

  defp walk("", _state, taken, _string, _locale, _supp) do
    {taken, ""}
  end

  defp walk(<<cp::utf8, rest::binary>> = remainder, state, taken, string, locale, suppressions) do
    case decide(state, cp, rest, taken, string, locale, suppressions) do
      :break ->
        {taken, remainder}

      {:no_break, new_state} ->
        walk(rest, new_state, taken + byte_size_utf8(cp), string, locale, suppressions)
    end
  end

  ## Decision

  # This is a direct, ordered transcription of the UAX #29 sentence-break
  # rule table (SB1–SB12). Its branch count mirrors the specification;
  # splitting it would obscure the one-to-one correspondence with the rules.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp decide(state, curr_cp, rest, taken, string, locale, suppressions) do
    {prev_actual, effective_prev, before_aterm, phase} = state
    curr = classify(locale, curr_cp)

    cond do
      # SB3: CR × LF (strict adjacency)
      prev_actual == :cr and curr == :lf ->
        {:no_break, advance(state, curr, curr_cp, locale)}

      # SB4: ParaSep ÷
      effective_prev in [:sep, :cr, :lf] ->
        :break

      # SB5: × (Extend | Format)
      curr in @transparent ->
        {:no_break, advance(state, curr, curr_cp, locale)}

      # SB6: ATerm × Numeric
      effective_prev == :aterm and curr == :numeric ->
        {:no_break, advance(state, curr, curr_cp, locale)}

      # SB7: (Upper|Lower) ATerm × Upper
      effective_prev == :aterm and curr == :upper and before_aterm in [:upper, :lower] ->
        {:no_break, advance(state, curr, curr_cp, locale)}

      # SB8a: SATerm Close* Sp* × (SContinue | SATerm)
      phase in [:aterm, :sterm, :aterm_close, :sterm_close, :aterm_sp, :sterm_sp] and
          curr in [:scontinue, :sterm, :aterm] ->
        {:no_break, advance(state, curr, curr_cp, locale)}

      # SB9: SATerm Close* × (Close | Sp | ParaSep)
      phase in [:aterm, :sterm, :aterm_close, :sterm_close] and
          curr in [:close, :sp, :sep, :cr, :lf] ->
        {:no_break, advance(state, curr, curr_cp, locale)}

      # SB10: SATerm Close* Sp* × (Sp | ParaSep)
      phase in [:aterm_sp, :sterm_sp] and curr in [:sp, :sep, :cr, :lf] ->
        {:no_break, advance(state, curr, curr_cp, locale)}

      # SB11: SATerm Close* Sp* ParaSep? ÷
      phase in [
        :aterm,
        :sterm,
        :aterm_close,
        :sterm_close,
        :aterm_sp,
        :sterm_sp,
        :aterm_parasep,
        :sterm_parasep
      ] ->
        decide_sb11(state, curr, curr_cp, rest, taken, string, locale, suppressions)

      # SB998: × Any (no break by default)
      true ->
        {:no_break, advance(state, curr, curr_cp, locale)}
    end
  end

  defp decide_sb11(state, curr, curr_cp, rest, taken, string, locale, suppressions) do
    {_, _, _, phase} = state
    aterm_led? = phase in [:aterm, :aterm_close, :aterm_sp, :aterm_parasep]

    sb8_suppress? =
      aterm_led? and phase != :aterm_parasep and sb8_lookahead?(curr, rest, locale)

    cond do
      sb8_suppress? ->
        {:no_break, advance(state, curr, curr_cp, locale)}

      aterm_led? and suppressed?(string, taken, locale, suppressions) ->
        {:no_break, advance(state, curr, curr_cp, locale)}

      true ->
        :break
    end
  end

  defp sb8_lookahead?(curr, rest, locale), do: sb8_lookahead_step(curr, rest, locale)

  defp sb8_lookahead_step(:lower, _rest, _locale), do: true

  defp sb8_lookahead_step(class, _rest, _locale)
       when class in [:oletter, :upper, :sep, :cr, :lf, :sterm, :aterm],
       do: false

  defp sb8_lookahead_step(_class, "", _locale), do: false

  defp sb8_lookahead_step(_class, <<cp::utf8, rest::binary>>, locale) do
    sb8_lookahead_step(classify(locale, cp), rest, locale)
  end

  ## Suppressions

  defp suppressed?(_string, _taken, _locale, suppressions) when suppressions == %MapSet{},
    do: false

  defp suppressed?(string, taken, locale, suppressions) do
    segment = binary_part(string, 0, taken)
    chars = :unicode.characters_to_list(segment) |> Enum.reverse()
    chars_after_tail = drop_tail(chars, locale)

    case chars_after_tail do
      [aterm_cp | rest_rev] ->
        if classify(locale, aterm_cp) == :aterm do
          word = trailing_word(rest_rev, locale)
          word != "" and MapSet.member?(suppressions, String.downcase(word))
        else
          false
        end

      [] ->
        false
    end
  end

  defp drop_tail([], _locale), do: []

  defp drop_tail([cp | rest] = all, locale) do
    case classify(locale, cp) do
      cls when cls in [:sep, :cr, :lf, :sp, :close, :extend, :format] ->
        drop_tail(rest, locale)

      _ ->
        all
    end
  end

  defp trailing_word(rev_chars, locale) do
    rev_chars
    |> Enum.take_while(&letter_like?(&1, locale))
    |> Enum.reverse()
    |> List.to_string()
  end

  defp letter_like?(cp, locale) do
    case classify(locale, cp) do
      cls when cls in [:upper, :lower, :oletter, :numeric, :extend, :format] -> true
      _ -> false
    end
  end

  ## State management

  defp initial_state(cp, locale) do
    cls = classify(locale, cp)

    phase =
      case cls do
        :aterm -> :aterm
        :sterm -> :sterm
        _ -> :none
      end

    {cls, if(cls in @transparent, do: :other, else: cls), :other, phase}
  end

  defp advance({_pa, eff_prev, before_aterm, phase}, curr_class, _curr_cp, _locale) do
    if curr_class in @transparent do
      {curr_class, eff_prev, before_aterm, phase}
    else
      new_before_aterm =
        case curr_class do
          :aterm -> eff_prev
          _ -> before_aterm
        end

      new_phase = next_phase(phase, eff_prev, curr_class)
      {curr_class, curr_class, new_before_aterm, new_phase}
    end
  end

  defp next_phase(_phase, _eff_prev, :aterm), do: :aterm
  defp next_phase(_phase, _eff_prev, :sterm), do: :sterm

  defp next_phase(phase, _eff_prev, :close)
       when phase in [:aterm, :aterm_close],
       do: :aterm_close

  defp next_phase(phase, _eff_prev, :close)
       when phase in [:sterm, :sterm_close],
       do: :sterm_close

  defp next_phase(phase, _eff_prev, :sp)
       when phase in [:aterm, :aterm_close, :aterm_sp],
       do: :aterm_sp

  defp next_phase(phase, _eff_prev, :sp)
       when phase in [:sterm, :sterm_close, :sterm_sp],
       do: :sterm_sp

  defp next_phase(phase, _eff_prev, sep_class)
       when sep_class in [:sep, :cr, :lf] and
              phase in [:aterm, :aterm_close, :aterm_sp],
       do: :aterm_parasep

  defp next_phase(phase, _eff_prev, sep_class)
       when sep_class in [:sep, :cr, :lf] and
              phase in [:sterm, :sterm_close, :sterm_sp],
       do: :sterm_parasep

  defp next_phase(_phase, _eff_prev, _curr_class), do: :none

  ## trailing_state_walk for break?/4

  defp trailing_state_walk("", _locale, _suppressions), do: {initial_state_empty(), 0}

  defp trailing_state_walk(string_before, locale, suppressions) do
    do_trailing(string_before, 0, 0, string_before, locale, suppressions, nil)
  end

  defp initial_state_empty, do: {:other, :other, :other, :none}

  defp do_trailing("", _seg_start, _consumed, _full, _locale, _supp, nil),
    do: {initial_state_empty(), 0}

  defp do_trailing("", seg_start, _consumed, _full, _locale, _supp, state),
    do: {state, seg_start}

  defp do_trailing(<<cp::utf8, rest::binary>>, seg_start, consumed, full, locale, supp, nil) do
    state = initial_state(cp, locale)
    cp_size = byte_size_utf8(cp)
    do_trailing(rest, seg_start, consumed + cp_size, full, locale, supp, state)
  end

  defp do_trailing(<<cp::utf8, rest::binary>>, seg_start, consumed, full, locale, supp, state) do
    seg_view = binary_part(full, seg_start, consumed - seg_start)
    cp_size = byte_size_utf8(cp)

    case decide(state, cp, rest, byte_size(seg_view), seg_view, locale, supp) do
      :break ->
        new_state = initial_state(cp, locale)
        do_trailing(rest, consumed, consumed + cp_size, full, locale, supp, new_state)

      {:no_break, new_state} ->
        do_trailing(rest, seg_start, consumed + cp_size, full, locale, supp, new_state)
    end
  end

  ## Locale-aware classification

  # Greek (`el`) extends $STerm to include U+003B (ASCII semicolon)
  # and U+037E (Greek question mark) per CLDR's el.xml. Both are
  # `:scontinue` by default in Unicode 17.0; under the `el` locale we
  # treat them as `:sterm` so that Greek text like `γδ; Ε` breaks at
  # the semicolon. Other locales fall through to the standard property.
  defp classify(:el, 0x003B), do: :sterm
  defp classify(:el, 0x037E), do: :sterm

  defp classify(_locale, cp), do: SentenceBreak.sentence_break(cp)

  ## utility

  defp byte_size_utf8(cp) when cp < 0x80, do: 1
  defp byte_size_utf8(cp) when cp < 0x800, do: 2
  defp byte_size_utf8(cp) when cp < 0x10000, do: 3
  defp byte_size_utf8(_cp), do: 4
end
