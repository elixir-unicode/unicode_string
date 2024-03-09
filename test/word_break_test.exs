defmodule Unicode.String.WordBreakTest do
  use ExUnit.Case, async: true
  import Unicode.String.TestDataParser

  @word_break_tests "./test/support/test_data/word_break_test.txt"

  # The following tests pass using the Unicode definition of $MidLetter but
  # CLDR makes some changes to that definition which causes the following test
  # lines to fail. For testing purposes we omit them.

  # Difference is in root.xml
  #
  # CLDR:
  #  <variable id="$MidLetter">[\p{Word_Break = MidLetter} - [\: \uFE55 \uFF1A]]</variable>
  #
  # Unicode:
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

  @test_lines 1..5000

  for {line, break, {left, _, _}, {right, _, _}} <- tests(@word_break_tests),
      line not in @cldr_specific_lines && line in @test_lines do
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

  test "Unicode.String.Break.split/2 when the passing rule is a :no_break" do
    assert Unicode.String.split(~s(“Hi), locale: :en, break: :word) == ["“", "Hi"]
    assert Unicode.String.split(~s("Du), locale: :de, break: :word) == ["\"", "Du"]
    assert Unicode.String.split(~s("Hi"), locale: :en, break: :word) == ["\"", "Hi", "\""]
    assert Unicode.String.split(~s("Hi ), locale: :en, break: :word) == ["\"", "Hi", " "]
  end

  test "Unicode.String.Break.next/2 when the passing rule is a :no_break" do
    assert Unicode.String.next(~s(“Hi), locale: :en, break: :word) == {"“", "Hi"}
    assert Unicode.String.next(~s("Du), locale: :de, break: :word) == {"\"", "Du"}
    assert Unicode.String.next(~s("Hi"), locale: :en, break: :word) ==  {"\"", "Hi\""}
    assert Unicode.String.next(~s("Hi ), locale: :en, break: :word) == {"\"", "Hi "}
  end

  test "Dictionary break" do
    assert Unicode.String.split("布鲁赫", locale: :zh) == ["布", "鲁", "赫"]
    assert Unicode.String.split("明德", locale: :zh_Hant) == ["明德"]
  end

  test "Resolving dictionary locales" do
    assert {:ok, :zh} = Unicode.String.Dictionary.dictionary_locale(:"zh-Hant")
    assert {:ok, :zh} = Unicode.String.Dictionary.dictionary_locale(:"zh-Hant-HK")
    assert {:ok, :zh} = Unicode.String.Dictionary.dictionary_locale(:yue)
    assert {:ok, :zh} = Unicode.String.Dictionary.dictionary_locale(:"yue-Hant")
  end

  test "split/2 with dictionary locales" do
    assert Unicode.String.split("明德", locale: :zh_Hant_HK) == ["明德"]
    assert Unicode.String.split("明德", locale: :zh_Hant) == ["明德"]
    assert Unicode.String.split("明德", locale: :yue) == ["明德"]
    assert Unicode.String.split("明德", locale: :yue_Hant) == ["明德"]
    assert Unicode.String.split("明德", locale: :zh) == ["明德"]
    assert Unicode.String.split("明德", locale: :ja) ==["明德"]
  end
end
