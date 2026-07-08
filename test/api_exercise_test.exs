defmodule Unicode.String.ApiExerciseTest do
  use ExUnit.Case, async: true

  alias Unicode.String
  alias Unicode.String.Break
  alias Unicode.String.Dictionary
  alias Unicode.String.DictionaryBreak
  alias Unicode.String.Segment

  describe "standalone grapheme break functions" do
    test "split/1, next/1 and break?/2" do
      assert Break.Grapheme.split("abc") == ["a", "b", "c"]
      assert Break.Grapheme.split("") == []
      assert Break.Grapheme.next("") == nil
      assert Break.Grapheme.break?("", "x")
      assert Break.Grapheme.break?("ab", "c")
    end
  end

  describe "standalone line break functions" do
    test "split/1, next/1 and break?/2" do
      assert Break.Line.split("a b c") == ["a ", "b ", "c"]
      assert Break.Line.split("") == []
      assert Break.Line.next("") == nil
      assert Break.Line.break?("", "x")
      assert Break.Line.break?("x", "")
      assert Break.Line.break?("ab ", "cd")
    end
  end

  describe "break?/2 through the public API for every break type" do
    test "grapheme and line with a multi-character prefix (exercises trailing state)" do
      assert String.break?({"ab", "c"}, break: :grapheme)
      assert String.break?({"ab ", "cd"}, break: :line)
    end

    test "an invalid break type raises" do
      assert_raise ArgumentError, fn ->
        String.break?({"a", "b"}, break: :not_a_break)
      end
    end
  end

  describe "split/stream trimming" do
    test "split/2 with :trim removes whitespace segments" do
      assert String.split("a b  c ", break: :word, trim: true) == ["a", "b", "c"]
    end

    test "stream/2 yields the same segments as split/2" do
      string = "The cat. The dog."

      assert string |> String.stream(break: :sentence) |> Enum.to_list() ==
               String.split(string, break: :sentence)
    end
  end

  describe "length-based locale guards" do
    test "is_language/is_script/is_territory classify by byte size" do
      require String

      classify = fn value ->
        cond do
          String.is_script(value) -> :script
          String.is_language(value) -> :language
          true -> :other
        end
      end

      assert classify.("en") == :language
      assert classify.("und") == :language
      assert classify.("Latn") == :script
      assert classify.("abcdef") == :other

      assert (case "US" do
                territory when String.is_territory(territory) -> :territory
                _ -> :other
              end) == :territory
    end
  end

  describe "DictionaryBreak direct entry points" do
    setup do
      Dictionary.load(:th)
      :ok
    end

    test "split/2 segments Thai text" do
      assert DictionaryBreak.split("สวัสดีเจ้านาย", :th) ==
               ["สวัสดี", "เจ้า", "นาย"]
    end

    test "split/2 and split_with_fallback/3 handle the empty string" do
      assert DictionaryBreak.split("", :th) == []
      assert DictionaryBreak.split_with_fallback("", :th, fn segment -> [segment] end) == []
    end

    test "Thai MAIYAMOK repetition mark is absorbed into the preceding word" do
      # นาน + ๆ (U+0E46) — the repetition mark attaches to the preceding word.
      assert DictionaryBreak.split("นานๆ", :th) == ["นานๆ"]
    end
  end

  describe "Break dispatch entry points" do
    test "break_at/4 accepts a bare string and the empty string" do
      assert Break.break_at("", :root, :grapheme_cluster_break, []) ==
               {:no_break, {"", {"", ""}}}

      assert Break.break_at("abc", :root, :grapheme_cluster_break, []) ==
               {:break, {"", {"", "abc"}}}
    end

    test "suppressions/2 and variables/2 fall back to empty lists" do
      assert Break.suppressions(:nonexistent_locale, :sentence_break) == []
      assert Break.variables(:nonexistent_locale, :sentence_break) == []
    end
  end

  describe "Segment suppression variables" do
    test "a segment type with suppressions yields a variable" do
      assert Segment.suppressions_variable("en", :sentence_break) != nil
    end

    test "a segment type without suppressions yields nil" do
      assert Segment.suppressions_variable("en", :word_break) == nil
    end
  end
end
