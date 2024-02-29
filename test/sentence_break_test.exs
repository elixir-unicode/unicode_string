defmodule Unicode.String.SentenceBreakTest do
  use ExUnit.Case, async: true
  import Unicode.String.TestDataParser

  @sentence_break_tests "./test/support/test_data/sentence_break_test.txt"

  @failing_lines []

  for {line, break, {left, _left_rule, _left_name}, {right, _right_rule, _right_name}} <-
        tests(@sentence_break_tests),
      line not in @failing_lines do
    if break == :"÷" do
      test "line #{line}: #{left} ÷ #{right}" do
        assert Unicode.String.break?({unquote(left), unquote(right)}, break: :sentence)
      end
    else
      test "line: #{line}: #{left} × #{right}" do
        refute Unicode.String.break?({unquote(left), unquote(right)}, break: :sentence)
      end
    end
  end
end
