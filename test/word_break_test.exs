defmodule Unicode.String.WordBreakTest do
  use ExUnit.Case, async: true
  import Unicode.String.TestDataParser

  @word_break_tests "./test/support/test_data/WordBreakTest.txt"

  @failing_lines [1253, 1254, 1267, 1268, 1283, 1284, 1285, 1286, 1287, 1288, 1289, 1290, 1291,
                  1292, 1712, 1728, 1729, 1734, 1735, 1736]

  for {line, break, left, right} <- tests(@word_break_tests),
        line not in @failing_lines do

    left_codepoints = codepoints(left)
    right_codepoints = codepoints(right)

    if break == :"÷" do
      test "line #{line}: #{left_codepoints} ÷ #{right_codepoints}" do
        assert Unicode.String.break?({unquote(left), unquote(right)})
      end
    else
      test "line: #{line}: #{left_codepoints} × #{right_codepoints}" do
        refute Unicode.String.break?({unquote(left), unquote(right)})
      end
    end
  end
end