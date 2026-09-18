defmodule Unicode.String.GraphemeBreakConformanceTest do
  use ExUnit.Case, async: true
  import Unicode.String.TestDataParser

  # Drives the full UAX #29 grapheme cluster conformance corpus
  # (`GraphemeBreakTest.txt`) against the public API. Unlike word breaking,
  # grapheme breaking has no locale tailoring, so every line is exercised.

  @grapheme_break_tests "./test/support/test_data/grapheme_break_test.txt"

  for {line, break, {left, _, _}, {right, _, _}} <- tests(@grapheme_break_tests) do
    left_codepoints = codepoints(left)
    right_codepoints = codepoints(right)

    case break do
      :"÷" ->
        test "grapheme break line #{line}: #{left_codepoints} ÷ #{right_codepoints}" do
          assert Unicode.String.break?({unquote(left), unquote(right)}, break: :grapheme)
        end

      :"×" ->
        test "grapheme break line #{line}: #{left_codepoints} × #{right_codepoints}" do
          refute Unicode.String.break?({unquote(left), unquote(right)}, break: :grapheme)
        end
    end
  end
end
