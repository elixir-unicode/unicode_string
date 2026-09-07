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
  # The ICU corpus is not all reachable, and a large part of it cannot be reached
  # by any implementation as the harness reads it. `IcuRbbiParser` keeps only the
  # `ss=` attribute of a `<locale>` line and discards the rest, so `ja`,
  # `ja@lb=loose`, `ja@lb=strict` and `ja@lw=phrase` all arrive labelled `"ja"`.
  # Several of those blocks carry the same input with different expected output —
  # one wants a break before a small kana and another wants it kept — so they
  # cannot all pass under one locale. Failures concentrate there: 42 of the 63 are
  # `ja` and 11 are `ko`.
  #
  # Making the corpus discriminate would mean preserving `lb=` on the parser side
  # and implementing the strict / normal / loose line break modes behind it. The
  # CLDR `ja.xml` tailoring itself (`CJ` as `$ID` rather than `$NS`) is
  # implemented — see `Unicode.String.Break.Tailoring` — and is net-neutral on
  # this corpus for exactly the reason above.
  @ucd_pass_floor 19_346
  @icu_pass_floor 177

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
