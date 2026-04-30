defmodule Unicode.String.Break.Sentence do
  @moduledoc """
  Single-pass DFA-style implementation of UAX #29 sentence break.

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
    Values:
      `:none`, `:aterm`, `:sterm`,
      `:aterm_close`, `:sterm_close`,
      `:aterm_sp`, `:sterm_sp`,
      `:aterm_parasep`, `:sterm_parasep`

    Phases prefixed `:aterm_*` track an ATerm-terminated sequence
    (which can be suppressed by SB8); `:sterm_*` track an STerm-only
    sequence (which cannot).

  ## Suppressions

  Locale-specific suppressions (e.g. "Mr.", "Dr.") are applied as a
  post-pass: when SB11 would fire after an ATerm-led sequence, the
  walker compares the trailing fragment of the segment against the
  suppression set and cancels the break on a longest-match.

  Locale data is bound at compile time by the `Suppressions` helper
  module.
  """

  alias Unicode.SentenceBreak

  @transparent [:extend, :format]

  @doc """
  Returns `{first_sentence, rest}` for `string`, or `nil` for empty input.

  Options:

  * `:suppressions` — a `MapSet` of trailing strings (lower-cased) that
    should suppress an otherwise-applicable SB11 break. Pass an empty
    `MapSet.new()` when no suppressions apply.
  """
  @spec next(String.t(), MapSet.t()) :: {String.t(), String.t()} | nil
  def next("", _suppressions), do: nil

  def next(string, suppressions) do
    {head_len, rest} = next_boundary(string, suppressions)
    {binary_part(string, 0, head_len), rest}
  end

  @doc "Splits `string` into sentences."
  @spec split(String.t(), MapSet.t()) :: [String.t()]
  def split("", _suppressions), do: []

  def split(string, suppressions) do
    {head, rest} = next(string, suppressions)
    [head | split(rest, suppressions)]
  end

  @doc """
  Boundary predicate. Returns `true` if there is a sentence break
  between `string_before` and `string_after`.

  When suppressing, the suppression check matches the trailing word
  of `string_before`.
  """
  @spec break?(String.t(), String.t(), MapSet.t()) :: boolean
  def break?("", _, _), do: true
  def break?(_, "", _), do: true

  def break?(string_before, <<curr_cp::utf8, rest::binary>> = string_after, suppressions) do
    {state, segment_offset} = trailing_state_walk(string_before, suppressions)
    full = string_before <> string_after

    case decide(state, curr_cp, rest, byte_size(string_before) - segment_offset,
           binary_part(full, segment_offset, byte_size(full) - segment_offset),
           suppressions) do
      :break -> true
      {:no_break, _} -> false
    end
  end

  # Walk `string_before` exactly as the splitter would, but only return
  # the final state and the byte offset at which the *current* segment
  # began. This lets break?/3 evaluate the boundary at end-of-prefix
  # with the same context the walker would have.
  defp trailing_state_walk("", _suppressions) do
    {initial_state_empty(), 0}
  end

  defp trailing_state_walk(string_before, suppressions) do
    do_trailing(string_before, 0, 0, string_before, suppressions, nil)
  end

  defp initial_state_empty, do: {:other, :other, :other, :none}

  defp do_trailing("", _seg_start, _consumed, _full, _supp, nil) do
    {initial_state_empty(), 0}
  end

  defp do_trailing("", seg_start, _consumed, _full, _supp, state) do
    {state, seg_start}
  end

  defp do_trailing(<<cp::utf8, rest::binary>>, seg_start, consumed, full, supp, nil) do
    state = initial_state(cp)
    cp_size = byte_size_utf8(cp)
    do_trailing(rest, seg_start, consumed + cp_size, full, supp, state)
  end

  defp do_trailing(<<cp::utf8, rest::binary>>, seg_start, consumed, full, supp, state) do
    seg_view = binary_part(full, seg_start, consumed - seg_start)
    cp_size = byte_size_utf8(cp)

    case decide(state, cp, rest, byte_size(seg_view), seg_view, supp) do
      :break ->
        # `cp` starts a new segment.
        new_state = initial_state(cp)
        do_trailing(rest, consumed, consumed + cp_size, full, supp, new_state)

      {:no_break, new_state} ->
        do_trailing(rest, seg_start, consumed + cp_size, full, supp, new_state)
    end
  end

  ## Walker

  defp next_boundary(<<cp::utf8, rest::binary>> = string, suppressions) do
    state = initial_state(cp)
    walk(rest, state, byte_size_utf8(cp), string, suppressions)
  end

  defp walk("", _state, taken, _string, _supp) do
    {taken, ""}
  end

  defp walk(<<cp::utf8, rest::binary>> = remainder, state, taken, string, suppressions) do
    case decide(state, cp, rest, taken, string, suppressions) do
      :break ->
        {taken, remainder}

      {:no_break, new_state} ->
        walk(rest, new_state, taken + byte_size_utf8(cp), string, suppressions)
    end
  end

  ## Decision

  defp decide(state, curr_cp, rest, taken, string, suppressions) do
    {prev_actual, effective_prev, before_aterm, phase} = state
    curr = SentenceBreak.sentence_break(curr_cp)

    cond do
      # SB3: CR × LF (strict adjacency)
      prev_actual == :cr and curr == :lf ->
        {:no_break, advance(state, curr, curr_cp)}

      # SB4: ParaSep ÷  (effective_prev is ParaSep i.e. :sep, or :cr/:lf)
      effective_prev in [:sep, :cr, :lf] ->
        :break

      # SB5: × (Extend | Format)
      curr in @transparent ->
        {:no_break, advance(state, curr, curr_cp)}

      # SB6: ATerm × Numeric
      effective_prev == :aterm and curr == :numeric ->
        {:no_break, advance(state, curr, curr_cp)}

      # SB7: (Upper|Lower) ATerm × Upper
      effective_prev == :aterm and curr == :upper and before_aterm in [:upper, :lower] ->
        {:no_break, advance(state, curr, curr_cp)}

      # SB8a: SATerm Close* Sp* × (SContinue | SATerm)
      phase in [:aterm, :sterm, :aterm_close, :sterm_close, :aterm_sp, :sterm_sp] and
          curr in [:scontinue, :sterm, :aterm] ->
        {:no_break, advance(state, curr, curr_cp)}

      # SB9: SATerm Close* × (Close | Sp | ParaSep)
      phase in [:aterm, :sterm, :aterm_close, :sterm_close] and
          curr in [:close, :sp, :sep, :cr, :lf] ->
        {:no_break, advance(state, curr, curr_cp)}

      # SB10: SATerm Close* Sp* × (Sp | ParaSep)
      phase in [:aterm_sp, :sterm_sp] and curr in [:sp, :sep, :cr, :lf] ->
        {:no_break, advance(state, curr, curr_cp)}

      # SB11: SATerm Close* Sp* ParaSep? ÷
      phase in [:aterm, :sterm, :aterm_close, :sterm_close, :aterm_sp, :sterm_sp,
                :aterm_parasep, :sterm_parasep] ->
        decide_sb11(state, curr, curr_cp, rest, taken, string, suppressions)

      # SB998: × Any (no break by default)
      true ->
        {:no_break, advance(state, curr, curr_cp)}
    end
  end

  # SB11 fires unless SB8 lookahead suppresses the break (only for
  # ATerm-led phases) and unless a locale suppression matches the
  # trailing fragment of the current segment.
  defp decide_sb11(state, curr, curr_cp, rest, taken, string, suppressions) do
    {_, _, _, phase} = state
    aterm_led? = phase in [:aterm, :aterm_close, :aterm_sp, :aterm_parasep]

    sb8_suppress? =
      aterm_led? and phase != :aterm_parasep and sb8_lookahead?(curr, rest)

    cond do
      sb8_suppress? ->
        {:no_break, advance(state, curr, curr_cp)}

      aterm_led? and suppressed?(string, taken, suppressions) ->
        {:no_break, advance(state, curr, curr_cp)}

      true ->
        :break
    end
  end

  # SB8: from ATerm Close* Sp*, scan forward through chars whose class
  # is NOT (OLetter | Upper | Lower | ParaSep | SATerm | sep | cr | lf);
  # if we reach a Lower before that set, suppress the break.
  defp sb8_lookahead?(curr, rest) do
    sb8_lookahead_step(curr, rest)
  end

  defp sb8_lookahead_step(:lower, _rest), do: true
  defp sb8_lookahead_step(class, _rest)
       when class in [:oletter, :upper, :sep, :cr, :lf, :sterm, :aterm],
       do: false

  defp sb8_lookahead_step(_class, ""), do: false

  defp sb8_lookahead_step(_class, <<cp::utf8, rest::binary>>) do
    sb8_lookahead_step(SentenceBreak.sentence_break(cp), rest)
  end

  ## Suppressions: longest-match against the trailing fragment of the
  ## current segment ending at the ATerm.
  defp suppressed?(_string, _taken, suppressions) when suppressions == %MapSet{}, do: false

  defp suppressed?(string, taken, suppressions) do
    segment = binary_part(string, 0, taken)
    chars = :unicode.characters_to_list(segment) |> Enum.reverse()

    # The segment ends with a `(SA)Term Close* Sp* ParaSep?` tail. Walk
    # back through any ParaSep, Sp, Close, transparent characters until
    # we land on the ATerm itself.
    chars_after_tail = drop_tail(chars)

    case chars_after_tail do
      [aterm_cp | rest_rev] ->
        if SentenceBreak.sentence_break(aterm_cp) == :aterm do
          word = trailing_word(rest_rev)
          word != "" and MapSet.member?(suppressions, String.downcase(word))
        else
          false
        end

      [] ->
        false
    end
  end

  defp drop_tail([]), do: []

  defp drop_tail([cp | rest] = all) do
    case SentenceBreak.sentence_break(cp) do
      cls when cls in [:sep, :cr, :lf, :sp, :close, :extend, :format] ->
        drop_tail(rest)

      _ ->
        all
    end
  end

  # `rev_chars` is a list of codepoints in reverse order. Take the
  # trailing word — the contiguous run of letter/mark codepoints that
  # ends just before the ATerm.
  defp trailing_word(rev_chars) do
    rev_chars
    |> Enum.take_while(&letter_like?/1)
    |> Enum.reverse()
    |> List.to_string()
  end

  defp letter_like?(cp) do
    case SentenceBreak.sentence_break(cp) do
      cls when cls in [:upper, :lower, :oletter, :numeric, :extend, :format] -> true
      _ -> false
    end
  end

  ## State management

  defp initial_state(cp) do
    cls = SentenceBreak.sentence_break(cp)

    phase =
      case cls do
        :aterm -> :aterm
        :sterm -> :sterm
        _ -> :none
      end

    effective =
      if cls in @transparent, do: :other, else: cls

    {cls, effective, :other, phase}
  end

  # Update the four-tuple state given the new char's class and codepoint.
  defp advance({_pa, eff_prev, before_aterm, phase}, curr_class, _curr_cp) do
    if curr_class in @transparent do
      # SB5 transparency: effective context unchanged; phase unchanged.
      # prev_actual updates to the new (transparent) class.
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

  ## Phase transitions for the SATerm Close* Sp* ParaSep? sequence.
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

  ## utility

  defp byte_size_utf8(cp) when cp < 0x80, do: 1
  defp byte_size_utf8(cp) when cp < 0x800, do: 2
  defp byte_size_utf8(cp) when cp < 0x10000, do: 3
  defp byte_size_utf8(_cp), do: 4
end
