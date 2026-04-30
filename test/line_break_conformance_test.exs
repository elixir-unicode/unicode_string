defmodule Unicode.String.LineBreakConformanceTest do
  use ExUnit.Case, async: true

  alias Unicode.String.IcuRbbiParser

  @ucd_path "./test/support/test_data/line_break_test.txt"
  @rbbi_path "./test/support/test_data/icu_rbbitst.txt"

  # Current passing-count baselines for the line-break engine. This
  # implementation covers the common LB rules used in realistic prose
  # (see Unicode.String.Break.Line); some UAX #14 corner cases (LB15
  # Pi/Pf variants, LB28a Brahmic clusters, EastAsian-width-aware LB30)
  # are approximated. The corpora below catch regressions; any drop
  # below the baseline fails the build, and improvements should raise
  # the baseline.
  @ucd_pass_floor 17_983
  @icu_pass_floor 113

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
