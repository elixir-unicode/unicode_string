defmodule Unicode.String.GraphemeBreakTest do
  use ExUnit.Case, async: true

  alias Unicode.String

  defp graphemes(string), do: String.split(string, break: :grapheme)

  describe "grapheme cluster breaking via the public API" do
    test "GB1/GB2: empty and single character" do
      assert graphemes("") == []
      assert graphemes("a") == ["a"]
    end

    test "GB3: CR × LF stays together" do
      assert graphemes("\r\n") == ["\r\n"]
    end

    test "GB4/GB5: CR, LF and Control are isolated" do
      assert graphemes("\r" <> "a") == ["\r", "a"]
      assert graphemes("a\n") == ["a", "\n"]
      assert graphemes("a" <> <<0x0007::utf8>>) == ["a", <<0x0007::utf8>>]
    end

    test "GB6/GB7/GB8: Hangul syllable sequences" do
      assert graphemes(<<0x1100::utf8, 0x1161::utf8>>) == [<<0x1100::utf8, 0x1161::utf8>>]
      assert graphemes(<<0xAC00::utf8, 0x11A8::utf8>>) == [<<0xAC00::utf8, 0x11A8::utf8>>]
      assert graphemes(<<0xAC01::utf8, 0x11A8::utf8>>) == [<<0xAC01::utf8, 0x11A8::utf8>>]
    end

    test "GB9: combining marks and ZWJ join the preceding base" do
      assert graphemes("e" <> <<0x0301::utf8>>) == ["e" <> <<0x0301::utf8>>]
    end

    test "GB9a: spacing marks join the preceding base" do
      assert graphemes(<<0x0915::utf8, 0x0903::utf8>>) == [<<0x0915::utf8, 0x0903::utf8>>]
    end

    test "GB9b: prepend characters join the following base" do
      assert graphemes(<<0x0600::utf8, 0x0661::utf8>>) == [<<0x0600::utf8, 0x0661::utf8>>]
    end

    test "GB9c: Indic consonant-linker-consonant forms one cluster" do
      indic = <<0x0915::utf8, 0x094D::utf8, 0x0915::utf8>>
      assert graphemes(indic) == [indic]
    end

    test "GB11: emoji ZWJ sequences form one cluster" do
      family = "👨‍👩‍👧"
      assert graphemes("a" <> family <> "b") == ["a", family, "b"]
    end

    test "GB12/GB13: regional indicator pairs (flags)" do
      assert graphemes("🇺🇸🇬🇧") == ["🇺🇸", "🇬🇧"]
      # An odd trailing regional indicator stands alone.
      assert graphemes("🇺🇸🇬🇧🇫") == ["🇺🇸", "🇬🇧", "🇫"]
    end

    test "GB999: unrelated characters always break" do
      assert graphemes("ab") == ["a", "b"]
    end
  end

  describe "break?/2 for graphemes" do
    test "boundaries at the string edges" do
      assert String.break?({"", "abc"}, break: :grapheme)
      assert String.break?({"abc", ""}, break: :grapheme)
    end

    test "no boundary inside a combining sequence" do
      refute String.break?({"e", <<0x0301::utf8>>}, break: :grapheme)
    end

    test "boundary between unrelated characters" do
      assert String.break?({"a", "b"}, break: :grapheme)
    end
  end

  describe "next/2 and splitter/2 for graphemes" do
    test "next/2 returns the first cluster and the remainder" do
      assert String.next("👨‍👩‍👧bc", break: :grapheme) == {"👨‍👩‍👧", "bc"}
    end

    test "splitter/2 is lazy and matches split/2" do
      string = "a👨‍👩‍👧🇺🇸b"

      assert string |> String.splitter(break: :grapheme) |> Enum.to_list() ==
               graphemes(string)
    end
  end
end
