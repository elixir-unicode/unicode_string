defmodule Unicode.String.WordBreakTest do
  use ExUnit.Case, async: true
  import Unicode.String.TestDataParser

  @word_break_tests "./test/support/test_data/word_break_test.txt"

  # The following tests pass using the Unicode definition of $MidLetter but
  # CLDR makes some changes to that definition which causes the following test
  # lines to fail. For testing purposes we omit them.

  # Difference is in root.xml
  #
  # Unicode:
  #  <variable id="$MidLetter">[\p{Word_Break = MidLetter} - [\: \uFE55 \uFF1A]]</variable>
  #
  # CLDR:
  #  <variable id="$MidLetter">[\p{Word_Break = MidLetter}]</variable>

  @cldr_specific_lines [
    1715,
    1253,
    1254,
    1267,
    1268,
    1283,
    1284,
    1285,
    1286,
    1287,
    1288,
    1289,
    1290,
    1291,
    1292,
    1712,
    1728,
    1729,
    1734,
    1735,
    1736
  ]

  # These tests current fail because "🛑" which is (OCTAGONAL SIGN (ExtPict))
  # doesn't have the property "extended pictographic" in the current release (15.1).
  @needs_unicode_16 [1731, 1738, 1737, 1732, 1739]

  @test_lines 1..5000

  for {line, break, {left, _, _}, {right, _, _}} <- tests(@word_break_tests),
      line not in (@cldr_specific_lines ++ @needs_unicode_16) && line in @test_lines do
    left_codepoints = codepoints(left)
    right_codepoints = codepoints(right)

    case break do
      :"÷" ->
        test "word break line #{line}: #{left_codepoints} ÷ #{right_codepoints}" do
          assert Unicode.String.break?({unquote(left), unquote(right)})
        end

      :"×" ->
        test "word break line #{line}: #{left_codepoints} × #{right_codepoints}" do
          refute Unicode.String.break?({unquote(left), unquote(right)})
        end
    end
  end
end
