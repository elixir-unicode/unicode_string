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

  test "Unicode.String.split/2 when the passing rule is a :no_break" do
    assert Unicode.String.split(~s(“Hi), locale: :en, break: :word) == ["“", "Hi"]
    assert Unicode.String.split(~s("Du), locale: :de, break: :word) == ["\"", "Du"]
    assert Unicode.String.split(~s("Hi"), locale: :en, break: :word) == ["\"", "Hi", "\""]
    assert Unicode.String.split(~s("Hi ), locale: :en, break: :word) == ["\"", "Hi", " "]
  end

  test "Unicode.String.next/2 when the passing rule is a :no_break" do
    assert Unicode.String.next(~s(“Hi), locale: :en, break: :word) == {"“", "Hi"}
    assert Unicode.String.next(~s("Du), locale: :de, break: :word) == {"\"", "Du"}
    assert Unicode.String.next(~s("Hi"), locale: :en, break: :word) == {"\"", "Hi\""}
    assert Unicode.String.next(~s("Hi ), locale: :en, break: :word) == {"\"", "Hi "}
  end

  # CLDR, unlike Unicode, applies a dictionary-based approach for word
  # breaks. Therefore there are no Unicode tests for these. We add them
  # here.

  test "Resolving dictionary locales" do
    assert {:ok, :zh} = Unicode.String.Dictionary.dictionary_locale(:"zh-Hant")
    assert {:ok, :zh} = Unicode.String.Dictionary.dictionary_locale(:"zh-Hant-HK")
    assert {:ok, :zh} = Unicode.String.Dictionary.dictionary_locale(:yue)
    assert {:ok, :zh} = Unicode.String.Dictionary.dictionary_locale(:"yue-Hant")
    assert {:ok, :zh} = Unicode.String.Dictionary.dictionary_locale(:"yue-Hans")
  end

  test "Unicode.String.split/2 uses a dictionary with dictionary locales" do
    assert Unicode.String.split("布鲁赫", locale: :zh) == ["布", "鲁", "赫"]

    assert Unicode.String.split("明德", locale: :zh_Hant_HK) == ["明德"]
    assert Unicode.String.split("明德", locale: :zh_Hant) == ["明德"]
    assert Unicode.String.split("明德", locale: :yue) == ["明德"]
    assert Unicode.String.split("明德", locale: :yue_Hant) == ["明德"]
    assert Unicode.String.split("明德", locale: :yue_Hans) == ["明德"]
    assert Unicode.String.split("明德", locale: :zh) == ["明德"]
    assert Unicode.String.split("明德", locale: :ja) == ["明德"]

    assert Unicode.String.split("สวัสดีเจ้านาย", locale: :th) == ["สวัสดี", "เจ้า", "นาย"]
    assert Unicode.String.split("ສະບາຍດີນາຍຈ້າງ", locale: :lo) == ["ສະບາຍດີ", "ນາຍ", "ຈ້າງ"]

    assert Unicode.String.split("ສະမင်္ဂလာပါ သူဌေး", locale: :my) == [
             "ສ",
             "ະ",
             "မင်္ဂလာ",
             "ပါ",
             " ",
             "သူဌေး"
           ]

    assert Unicode.String.split("ສជំរាបសួរចៅហ្វាយ", locale: :km) == ["ສ", "ជំរាបសួរ", "ចៅហ្វាយ"]
  end

  test "Doesn't break after a word-break=extend codepoint when followed by a letter" do
    assert ["Ẹ́va", "Sophia"] ==
             Unicode.String.split("Ẹ́va Sophia", locale: :pcm, trim: true, break: :word)
  end

  # A dictionary only knows how to segment the script(s) it covers. Applying it
  # to text in any other script shatters that text into single characters, so
  # the standard rules have to govern everything outside a dictionary script run.

  test "Unicode.String.split/2 applies the standard rules outside a dictionary script" do
    assert Unicode.String.split("Japanese", locale: :ja, trim: true) == ["Japanese"]
    assert Unicode.String.split("100", locale: :ja, trim: true) == ["100"]
    assert Unicode.String.split("hello world", locale: :ja, trim: true) == ["hello", "world"]

    for locale <- [:zh, :ja, :th, :lo, :my, :km] do
      assert Unicode.String.split("hello world", locale: locale, trim: true) ==
               ["hello", "world"]

      assert Unicode.String.split("100", locale: locale, trim: true) == ["100"]
    end
  end

  test "Unicode.String.split/2 breaks mixed script text with the dictionary and the rules" do
    assert Unicode.String.split("日本語 100 km", locale: :ja, trim: true) ==
             ["日本語", "100", "km"]

    assert Unicode.String.split("ISO 8601形式の日付", locale: :ja, trim: true) ==
             ["ISO", "8601", "形式", "の", "日付"]

    assert Unicode.String.split("サンプルCSVファイル", locale: :ja, trim: true) ==
             ["サンプル", "CSV", "ファイル"]

    assert Unicode.String.split("hello สวัสดี world", locale: :th, trim: true) ==
             ["hello", "สวัสดี", "world"]

    assert Unicode.String.split("hello ជំរាបសួរ world", locale: :km, trim: true) ==
             ["hello", "ជំរាបសួរ", "world"]
  end

  test "Unicode.String.split/2 keeps dictionary script runs intact" do
    # ー (U+30FC) is Script=Common but is part of a Japanese run
    assert Unicode.String.split("キロメートル", locale: :ja, trim: true) == ["キロメートル"]

    assert Unicode.String.split("日本語のテキスト", locale: :ja, trim: true) ==
             ["日本語", "の", "テキスト"]

    # WB13b ($ExtendNumLet × $Katakana) joins these under the standard rules
    # but the dictionary has to be the one to break the Katakana run
    assert Unicode.String.split("abc_キロメートル", locale: :root) == ["abc_キロメートル"]
    assert Unicode.String.split("abc_キロメートル", locale: :ja) == ["abc_", "キロメートル"]
  end

  test "Unicode.String.split/2 with a dictionary locale preserves the string" do
    strings = [
      "日本語 100 km",
      "iPhone 15 Proの価格は199,800円です",
      "  日本語  ",
      "abc日本語def",
      "hello สวัสดี world",
      "hello ជំរាបសួរ world",
      "日本語、テキスト。"
    ]

    for string <- strings, locale <- [:ja, :zh, :th, :lo, :my, :km] do
      options = [break: :word, locale: locale]

      assert Enum.join(Unicode.String.split(string, options)) == string

      assert Enum.to_list(Unicode.String.stream(string, options)) ==
               Unicode.String.split(string, options)
    end
  end
end
