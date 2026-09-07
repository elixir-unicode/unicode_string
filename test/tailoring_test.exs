defmodule Unicode.String.TailoringTest do
  use ExUnit.Case, async: true

  alias Unicode.String.Break.Tailoring

  doctest Unicode.String.Break.Tailoring

  describe "sentence break tailoring (el)" do
    test "Greek breaks at the erotimatiko where other locales do not" do
      text = "γδ; Ε ζη. Θι"

      assert Unicode.String.split(text, break: :sentence, locale: :el) ==
               ["γδ; ", "Ε ζη. ", "Θι"]

      assert Unicode.String.split(text, break: :sentence, locale: :en) ==
               ["γδ; Ε ζη. ", "Θι"]
    end

    test "U+037E GREEK QUESTION MARK is tailored and survives into the output" do
      text = "γδ" <> <<0x037E::utf8>> <> " Ε ζη"

      assert [first, _rest] = Unicode.String.split(text, break: :sentence, locale: :el)
      assert first == "γδ" <> <<0x037E::utf8>> <> " "
      assert Unicode.String.split(text, break: :sentence, locale: :en) == [text]
    end

    test "the substitution preserves byte length" do
      for text <- ["γδ; Ε", "γδ" <> <<0x037E::utf8>> <> " Ε"] do
        assert byte_size(Tailoring.tailor(text, :el, :sentence)) == byte_size(text)
      end
    end
  end

  describe "line break tailoring (ja, zh, zh_Hant)" do
    test "a conditional Japanese starter breaks as an ideograph, not a non-starter" do
      # U+3041 HIRAGANA LETTER SMALL A is Line_Break=Conditional_Japanese_Starter.
      text = "あぁx"

      assert Unicode.String.split(text, break: :line, locale: :root) == ["あぁ", "x"]

      for locale <- [:ja, :zh, :"zh-Hant"] do
        assert Unicode.String.split(text, break: :line, locale: locale) == ["あ", "ぁ", "x"]
      end
    end

    test "the tailored character survives into the output" do
      assert ["あ", small_a, "x"] = Unicode.String.split("あぁx", break: :line, locale: :ja)
      assert small_a == <<0x3041::utf8>>
    end

    test "the substitution preserves byte length for both encodings" do
      # U+3041 encodes to three bytes, U+1B132 to four.
      for text <- ["あぁx", "あ" <> <<0x1B132::utf8>> <> "x"] do
        assert byte_size(Tailoring.tailor(text, :ja, :line)) == byte_size(text)
      end
    end

    test "untailored locales are unaffected" do
      assert Tailoring.tailor("あぁx", :en, :line) == "あぁx"
      assert Tailoring.tailor("あぁx", :ja, :sentence) == "あぁx"
    end
  end

  describe "suppressions" do
    test "a suppressed abbreviation does not end a sentence" do
      text = "Hello Mr. Smith. How are you?"

      assert Unicode.String.split(text, break: :sentence, locale: :en) ==
               ["Hello Mr. Smith. ", "How are you?"]

      assert Unicode.String.split(text, break: :sentence, locale: :en, suppressions: false) ==
               ["Hello Mr. ", "Smith. ", "How are you?"]
    end

    test "an STerm is never suppressed" do
      assert Tailoring.suppressed?("Hello Mr!", :en, MapSet.new(["mr"])) == false
    end

    test "invalid UTF-8 is not a suppression and does not raise" do
      assert Tailoring.suppressed?(<<0xFF, 0xFE>>, :en, MapSet.new(["mr"])) == false
    end

    test "an empty suppression set suppresses nothing" do
      assert Tailoring.suppressed?("Hello Mr.", :en, MapSet.new()) == false
    end
  end
end
