defmodule Unicode.String.LineBreakConformanceTest do
  use ExUnit.Case, async: true

  alias Unicode.String.IcuRbbiParser

  @ucd_path "./test/support/test_data/line_break_test.txt"
  @rbbi_path "./test/support/test_data/icu_rbbitst.txt"

  # Current passing-count baselines for the line-break engine. The
  # engine covers the rules used in realistic prose (see
  # `Unicode.String.Break.Line` for full coverage). The corpora below
  # catch regressions: any drop below the baseline fails the build,
  # and improvements should raise the baseline.
  #
  # Known categories of remaining failures (documented in
  # `Unicode.String.Break.Line`'s "Limitations" section):
  #
  # * **CJK loose / normal / strict tailoring** — ICU's `<line>` rules
  #   in `rbbitst.txt` expect Japanese-locale loose-mode behaviour
  #   (e.g. `CJ → ID`, ID × HY breakable, breaks between Hiragana/
  #   Katakana). This module implements only standard `CJ → NS`.
  #   This accounts for the majority of the remaining ICU failures.
  #
  # * **LB15a / LB15b (Pi / Pf quotation)** — initial- and final-
  #   quote subclasses are folded into plain QU.
  #
  # * **LB28a (Brahmic clusters)** — Indic AK/AP/AS/VI/VF clusters
  #   are not handled.
  #
  # * **LB30 East-Asian-width sensitivity** — LB30 (AL|HL|NU) × OP
  #   does not distinguish F/W/H widths from others.
  @ucd_pass_floor 18_657
  @icu_pass_floor 162

  describe "Unicode UCD LineBreakTest.txt (#{@ucd_pass_floor} of 19_338 cases must pass)" do
    test "minimum-pass-count baseline" do
      tests = Unicode.String.TestDataParser.parse(@ucd_path)
      total = length(tests)

      passing =
        Enum.count(tests, fn {_line, parts} ->
          {input, expected} = build_input_and_expected(parts)
          Unicode.String.split(input, break: :line) == expected
        end)

      assert passing >= @ucd_pass_floor,
             "regression: line-break passes only #{passing} of #{total} UCD cases " <>
               "(baseline #{@ucd_pass_floor})"
    end
  end

  describe "ICU rbbitst.txt line-break corpus (#{@icu_pass_floor} of ~240 cases must pass)" do
    test "minimum-pass-count baseline" do
      blocks =
        @rbbi_path
        |> IcuRbbiParser.parse()
        |> Enum.filter(&(&1.mode == :line))

      total = length(blocks)

      passing =
        Enum.count(blocks, fn b ->
          actual =
            Unicode.String.split(b.input,
              break: :line,
              locale: b.locale,
              suppressions: b.suppressions?
            )

          actual == b.expected
        end)

      assert passing >= @icu_pass_floor,
             "regression: line-break passes only #{passing} of #{total} ICU cases " <>
               "(baseline #{@icu_pass_floor})"
    end
  end

  ## ---------------------------------------------------------------- helper

  defp build_input_and_expected(parts) do
    {input, segments_rev, current} =
      Enum.reduce(parts, {"", [], ""}, fn
        {char, _}, {input, segs, cur} when is_binary(char) ->
          {input <> char, segs, cur <> char}

        {op, _}, {input, segs, cur} ->
          case op do
            :"÷" ->
              if cur == "", do: {input, segs, ""}, else: {input, [cur | segs], ""}

            :"×" ->
              {input, segs, cur}
          end
      end)

    expected =
      if current == "",
        do: Enum.reverse(segments_rev),
        else: Enum.reverse([current | segments_rev])

    {input, expected}
  end
end
