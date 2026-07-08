defmodule Unicode.String.Break.Line do
  @moduledoc """
  Single-pass line-break implementation following UAX #14.

  This is a pragmatic pair-table evaluator covering the rules used in
  realistic prose: the LB1 resolution of ambiguous classes, mandatory
  breaks (LB4–LB6), spaces (LB7–LB8a, LB18), combining marks (LB9–LB10),
  word-joiner / glue / quotation behavior (LB11–LB12a, LB19), the LB13
  cluster of close/postfix punctuation, the OP/CL pair (LB14–LB17),
  the LB15c/LB15d numeric-prefix carve-out, the LB20a word-initial
  hyphen rule, the LB21a Hebrew-letter trailing hyphen rule,
  Brahmic / numeric / alphabetic continuations (LB22–LB30b), the
  Hangul rules (LB26–LB27), Regional_Indicator parity (LB30a), and
  emoji-modifier (LB30b).

  Trailing space-runs are tracked via a small state vector rather than
  re-scanned each step, so each character costs O(1).

  ## Limitations and known gaps

  Line breaking is by far the largest UAX #14 algorithm and ICU layers
  several locale-specific tailorings on top of it. The following parts
  are not currently implemented; on the conformance corpora these are
  the dominant remaining failures:

  * **CJK locale tailoring (loose / normal / strict).** ICU ships
    separate rule files (`line_loose_cj.txt`, `line_normal_cj.txt`,
    `line_strict_cj.txt`) that adjust break behaviour around CJK
    characters and small-kana / hyphen / iteration marks. Notably:

    - In *loose* mode `CJ` resolves to `ID` and break opportunities
      are introduced between Hiragana/Katakana characters.
    - In *normal* mode (the standard UAX default) `CJ` resolves to
      `NS`, which prevents most breaks within Japanese.
    - ID × HY in CJK contexts is permitted to break to support
      Japanese hyphen usage like `あ‐1`.

    This module currently implements only the standard mode (`CJ →
    NS`). Several Japanese-locale cases in ICU's `rbbitst.txt`
    expect loose-mode behaviour and therefore differ.

  * **LB15a / LB15b (Pi / Pf quotation).** Initial-quote and
    final-quote sub-classes of `QU` are treated as plain `QU`. The
    east-asian-width-aware variants in LB15a/15b are approximated.

  * **LB28a (Brahmic clusters).** Indic conjunct clusters
    (`AK`/`AP`/`AS`/`VI`/`VF`) follow the default break rules rather
    than the Brahmic-specific cluster handling.

  * **LB30 East-Asian-width sensitivity.** LB30 should distinguish
    between F/W/H and other East-Asian-width values when deciding
    whether `(AL|HL|NU) × OP` and `CP × (AL|HL|NU)` apply. This
    implementation applies the rule uniformly.

  These gaps are tracked by the line-break conformance regression
  tests in `test/line_break_conformance_test.exs`.

  ## State

  * `effective_prev` — the previous non-CM/non-ZWJ class, after LB1
    resolution and LB9 (combining marks taking the class of their base).
  * `prev_actual` — the immediately previous class, for LB5 (CR×LF).
  * `space_run` — `:none`, `:after_op`, `:after_qu`, `:after_cl`,
    `:after_b2`, or `:after_zw`. Tracks the `X SP*` patterns required
    by LB14, LB15, LB16, LB17, and LB8.
  * `ri_parity` — `:odd` / `:even` for LB30a.
  """

  alias Unicode.LineBreak

  ## Public API

  @doc "Returns `{first_segment, rest}` or `nil` for the empty string."
  @spec next(String.t()) :: {String.t(), String.t()} | nil
  def next(""), do: nil

  def next(string) do
    {len, rest} = next_boundary(string)
    {binary_part(string, 0, len), rest}
  end

  @doc "Splits `string` into line-break segments."
  @spec split(String.t()) :: [String.t()]
  def split(""), do: []

  def split(string) do
    {head, rest} = next(string)
    [head | split(rest)]
  end

  @doc "Boundary predicate for a `{before, after}` pair."
  @spec break?(String.t(), String.t()) :: boolean
  def break?("", _), do: true
  def break?(_, ""), do: true

  def break?(before, <<curr_cp::utf8, rest::binary>>) do
    state = trailing_state(before)
    decide_op(state, classify(curr_cp), rest) == :break
  end

  ## Walker

  defp next_boundary(<<cp::utf8, rest::binary>> = string) do
    cls = classify(cp)
    state = initial_state(cls)
    walk(rest, state, byte_size_utf8(cp), string)
  end

  defp walk("", _state, taken, _string), do: {taken, ""}

  defp walk(<<cp::utf8, rest::binary>> = remainder, state, taken, string) do
    cls = classify(cp)

    case decide_op(state, cls, rest) do
      :break ->
        {taken, remainder}

      :no_break ->
        new_state = advance(state, cls)
        walk(rest, new_state, taken + byte_size_utf8(cp), string)
    end
  end

  ## Class resolution (LB1, plus partial LB9 for prev/curr)

  # LB1: AI, SG, XX → AL; SA → AL or CM (we treat as AL for non-Mn/Mc; CM for Mn/Mc — approximated as AL); CJ → NS.
  # We do not currently distinguish SA-Mn/Mc; treating SA as AL is acceptable for the pair table.
  @lb1_map %{
    ai: :al,
    sg: :al,
    xx: :al,
    sa: :al,
    cj: :ns,
    # The unicode dep classifies U+2010 etc. as :hh; UAX #14 itself
    # uses :hy (Hyphen). Treat them identically.
    hh: :hy
  }

  defp classify(cp) do
    raw = LineBreak.line_break(cp)
    Map.get(@lb1_map, raw, raw)
  end

  ## State

  defp initial_state(cls) do
    {ri_parity, _} =
      if cls == :ri, do: {:odd, true}, else: {:even, false}

    space_run =
      case cls do
        :op -> :after_op
        :qu -> :after_qu
        :cl -> :after_cl
        :cp -> :after_cl
        :b2 -> :after_b2
        :zw -> :after_zw
        _ -> :none
      end

    # `:sot` (start-of-text) is the eff_prev2 sentinel for the very first
    # character; this lets LB20a recognise word-initial hyphens at the
    # beginning of input (^(HY|HH) AL → no break).
    {cls, :sot, cls, space_run, ri_parity}
  end

  defp advance({eff_prev, eff_prev2, _prev_actual, space_run, ri_parity}, cls) do
    # eff_prev2 is the previous *non-transparent* class — it's preserved
    # when curr is CM/ZWJ (LB9 transparency) and otherwise rolls forward.
    new_eff_prev2 = if cls in [:cm, :zwj], do: eff_prev2, else: eff_prev

    {next_eff_prev(cls, eff_prev), new_eff_prev2, cls, next_space_run(cls, space_run),
     next_ri_parity(cls, ri_parity)}
  end

  # RI runs toggle odd/even parity so LB30a can pair regional indicators;
  # any other class resets the run.
  defp next_ri_parity(:ri, :odd), do: :even
  defp next_ri_parity(:ri, :even), do: :odd
  defp next_ri_parity(_cls, _ri_parity), do: :even

  # Track the "space run" context used by the space-sensitive rules.
  # LB9: CM/ZWJ take the class of the base, so the run is left unchanged.
  defp next_space_run(:sp, space_run), do: space_run
  defp next_space_run(:op, _space_run), do: :after_op
  defp next_space_run(:qu, _space_run), do: :after_qu
  defp next_space_run(cls, _space_run) when cls in [:cl, :cp], do: :after_cl
  defp next_space_run(:b2, _space_run), do: :after_b2
  defp next_space_run(:zw, _space_run), do: :after_zw
  defp next_space_run(cls, space_run) when cls in [:cm, :zwj], do: space_run
  defp next_space_run(_cls, _space_run), do: :none

  # LB9: CM and ZWJ take the class of the preceding character, except when
  # that character is BK, CR, LF, NL, SP, or ZW (then they default to AL by
  # LB10).
  defp next_eff_prev(cls, eff_prev) when cls in [:cm, :zwj] do
    if eff_prev in [:bk, :cr, :lf, :nl, :sp, :zw], do: :al, else: eff_prev
  end

  defp next_eff_prev(cls, _eff_prev), do: cls

  defp trailing_state(string_before) do
    [first | rest] = String.to_charlist(string_before)
    state = initial_state(classify(first))
    Enum.reduce(rest, state, fn cp, st -> advance(st, classify(cp)) end)
  end

  ## Decision

  # decide_op({eff_prev, eff_prev2, prev_actual, space_run, ri_parity}, curr, rest)
  # `rest` is the binary after `curr`; some rules require a 1-char lookahead.
  #
  # This is a direct, ordered transcription of the UAX #14 line-break rule
  # table (LB4–LB31). Its branch count mirrors the specification; splitting
  # it would obscure the one-to-one correspondence with the rules.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp decide_op({eff_prev, eff_prev2, prev_actual, space_run, ri_parity}, curr, rest) do
    cond do
      # LB4: BK !
      eff_prev == :bk ->
        :break

      # LB5: CR × LF; CR/LF/NL !
      prev_actual == :cr and curr == :lf ->
        :no_break

      eff_prev in [:cr, :lf, :nl] ->
        :break

      # LB6: × (BK | CR | LF | NL)
      curr in [:bk, :cr, :lf, :nl] ->
        :no_break

      # LB7: × SP, × ZW
      curr in [:sp, :zw] ->
        :no_break

      # LB8: ZW SP* ÷
      space_run == :after_zw ->
        :break

      # LB8a: ZWJ × — no break after a ZWJ. We check `prev_actual` (the
      # immediate-previous class) rather than `eff_prev`, because LB9
      # transparency rolls eff_prev past the ZWJ to its base.
      prev_actual == :zwj ->
        :no_break

      # LB9: × CM / × ZWJ — combining marks attach to their base.
      # LB10 carve-out: when the preceding char has no base (BK, CR, LF,
      # NL, SP, ZW), the CM/ZWJ doesn't attach; it is reclassified as
      # AL and the surrounding rules (LB4, LB5, LB8, LB18) decide the
      # break. advance/2 takes care of the reclassification.
      curr in [:cm, :zwj] and eff_prev not in [:bk, :cr, :lf, :nl, :sp, :zw] ->
        :no_break

      # LB11: × WJ, WJ ×
      curr == :wj or eff_prev == :wj ->
        :no_break

      # LB12: GL ×
      eff_prev == :gl ->
        :no_break

      # LB12a: [^SP BA HY] × GL
      curr == :gl and eff_prev not in [:sp, :ba, :hy] ->
        :no_break

      # LB14: OP SP* ×  — must come before LB15c so that "OP SP IS NU"
      # doesn't break (e.g. "( .789").
      space_run == :after_op ->
        :no_break

      # LB15: QU SP* × OP  (simplified — full LB15 has Pi/Pf variants)
      space_run == :after_qu and curr == :op ->
        :no_break

      # LB16: (CL | CP) SP* × NS
      space_run == :after_cl and curr == :ns ->
        :no_break

      # LB17: B2 SP* × B2
      space_run == :after_b2 and curr == :b2 ->
        :no_break

      # LB15c: SP ÷ IS NU — break before an IS that begins a number
      # and follows a space (e.g. "start .789").
      eff_prev == :sp and curr == :is and peek_class(rest) == :nu ->
        :break

      # LB15d: × IS — otherwise no break before IS.
      curr == :is ->
        :no_break

      # LB13: × CL, × CP, × EX, × SY.
      curr in [:cl, :cp, :ex, :sy] ->
        :no_break

      # LB18: SP ÷  (covered as default break since no rule fired)
      eff_prev == :sp ->
        :break

      # LB19: × QU, QU ×
      curr == :qu or eff_prev == :qu ->
        :no_break

      # LB20: ÷ CB; CB ÷
      curr == :cb or eff_prev == :cb ->
        :break

      # LB20a: Do not break after a word-initial hyphen.
      # ^(HY | HH) (AL | HL) — at start of text or after a space-/
      # break-class character. (HH is mapped to HY by LB1.)
      eff_prev == :hy and curr in [:al, :hl] and
          eff_prev2 in [:sot, :bk, :cr, :lf, :nl, :sp, :zw, :cb, :gl] ->
        :no_break

      # LB21: × BA, × HY, × NS; BB ×
      curr in [:ba, :hy, :ns] or eff_prev == :bb ->
        :no_break

      # LB21a: HL (HY | BA) × — no break after a Hebrew letter followed
      # by hyphen or break-after.
      eff_prev2 == :hl and eff_prev in [:hy, :ba] ->
        :no_break

      # LB21b: SY × HL
      eff_prev == :sy and curr == :hl ->
        :no_break

      # LB22: × IN
      curr == :in ->
        :no_break

      # LB23: (AL | HL) × NU; NU × (AL | HL)
      eff_prev in [:al, :hl] and curr == :nu ->
        :no_break

      eff_prev == :nu and curr in [:al, :hl] ->
        :no_break

      # LB23a: PR × (ID | EB | EM); (ID | EB | EM) × PO
      eff_prev == :pr and curr in [:id, :eb, :em] ->
        :no_break

      eff_prev in [:id, :eb, :em] and curr == :po ->
        :no_break

      # LB24: (PR | PO) × (AL | HL); (AL | HL) × (PR | PO)
      eff_prev in [:pr, :po] and curr in [:al, :hl] ->
        :no_break

      eff_prev in [:al, :hl] and curr in [:pr, :po] ->
        :no_break

      # LB25 (subset): numeric expressions — keep numeric runs intact.
      eff_prev in [:cl, :cp, :nu] and curr in [:po, :pr] ->
        :no_break

      eff_prev in [:po, :pr] and curr in [:op, :nu] ->
        :no_break

      eff_prev in [:hy, :is, :nu, :sy] and curr == :nu ->
        :no_break

      # LB26: Hangul syllables
      eff_prev == :jl and curr in [:jl, :jv, :h2, :h3] ->
        :no_break

      eff_prev in [:jv, :h2] and curr in [:jv, :jt] ->
        :no_break

      eff_prev in [:jt, :h3] and curr == :jt ->
        :no_break

      # LB27: Hangul / numeric prefix-postfix
      eff_prev in [:jl, :jv, :jt, :h2, :h3] and curr == :po ->
        :no_break

      eff_prev == :pr and curr in [:jl, :jv, :jt, :h2, :h3] ->
        :no_break

      # LB28: (AL | HL) × (AL | HL)
      eff_prev in [:al, :hl] and curr in [:al, :hl] ->
        :no_break

      # LB29: IS × (AL | HL)
      eff_prev == :is and curr in [:al, :hl] ->
        :no_break

      # LB30: (AL | HL | NU) × OP; CP × (AL | HL | NU)
      # (full LB30 has East-Asian-width restrictions we approximate).
      eff_prev in [:al, :hl, :nu] and curr == :op ->
        :no_break

      eff_prev == :cp and curr in [:al, :hl, :nu] ->
        :no_break

      # LB30a: RI RI (parity even after the pair forms) — keep odd-RI×RI
      eff_prev == :ri and curr == :ri and ri_parity == :odd ->
        :no_break

      # LB30b: EB × EM; default EM-base × EM (approximated as ID × EM
      # already handled by LB23a path).
      eff_prev == :eb and curr == :em ->
        :no_break

      # LB31: default break.
      true ->
        :break
    end
  end

  # Look at the first codepoint of `rest`, skipping over CM and ZWJ
  # (LB9 transparency), and return its line-break class. `nil` if rest
  # is empty.
  defp peek_class(""), do: nil

  defp peek_class(<<cp::utf8, rest::binary>>) do
    case classify(cp) do
      cls when cls in [:cm, :zwj] -> peek_class(rest)
      cls -> cls
    end
  end

  ## utility

  defp byte_size_utf8(cp) when cp < 0x80, do: 1
  defp byte_size_utf8(cp) when cp < 0x800, do: 2
  defp byte_size_utf8(cp) when cp < 0x10000, do: 3
  defp byte_size_utf8(_cp), do: 4
end
