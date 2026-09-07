defmodule Unicode.String.LineBreakConformanceTest do
  use ExUnit.Case, async: true

  alias Unicode.String.IcuRbbiParser

  @ucd_path "./test/support/test_data/line_break_test.txt"
  @rbbi_path "./test/support/test_data/icu_rbbitst.txt"

  # Passing-count baselines for line breaking. The corpora below catch
  # regressions: any drop below the baseline fails the build, and improvements
  # should raise the baseline.
  #
  # The UCD floor is the whole corpus. Line breaking is fully conformant against
  # `LineBreakTest.txt` and any failure at all is a regression.
  #
  # Most of the ICU corpus that fails is not testing UAX #14. Of the 57 failures,
  # grouped by the full `<locale>` directive rather than by the base locale:
  #
  # * 45 are `lw=phrase` (38 `ja`, 7 `ko`) — phrase-based line breaking, a
  #   separate ICU feature driven by a dictionary, not a tailoring of UAX #14.
  #
  # * 6 are `lb=loose`, `lb=normal` or `lb=strict` — the CSS line break modes,
  #   which are not implemented.
  #
  # * 6 are dictionary segmentation differences in Thai and Burmese: which words
  #   the dictionary chooses.
  #
  # None is attributable to the line break rules themselves. Every plain-locale
  # block not depending on the dictionary passes: `root` 18/18, `ko` 10/10,
  # `ja` 5/5, `fi` 6/6.
  #
  # `IcuRbbiParser` collapses `ja@lb=loose` and `ja` to one label, and blocks
  # under those two pair the same input with different expected output, so no
  # implementation can satisfy both at once as the corpus is read here. Raising
  # the ceiling means preserving `lb=` in the parser and implementing the modes
  # behind it.
  @ucd_pass_floor 19_346
  @icu_pass_floor 179

  describe "Unicode UCD LineBreakTest.txt (#{@ucd_pass_floor} of 19_346 cases must pass)" do
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

        {:"÷", _}, {input, segs, cur} ->
          if cur == "", do: {input, segs, ""}, else: {input, [cur | segs], ""}

        {:"×", _}, {input, segs, cur} ->
          {input, segs, cur}
      end)

    expected =
      if current == "",
        do: Enum.reverse(segments_rev),
        else: Enum.reverse([current | segments_rev])

    {input, expected}
  end
end
