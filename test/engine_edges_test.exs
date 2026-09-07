defmodule Unicode.String.EngineEdgesTest do
  use ExUnit.Case, async: true

  alias Unicode.String.Break
  alias Unicode.String.Break.Tailoring
  alias Unicode.String.Dfa

  @suppressions MapSet.new(["mr"])

  describe "tailoring is a no-op where a locale defines none" do
    test "break types without any tailoring pass the string through" do
      for break_type <- [:word, :grapheme, :line, :sentence] do
        assert Tailoring.tailor("abc", :en, break_type) == "abc"
      end

      assert Tailoring.tailor("abc", :ja, :word) == "abc"
      assert Tailoring.tailor("abc", :el, :line) == "abc"
    end

    test "classify falls through to the untailored property" do
      assert Tailoring.classify(:en, ?.) == :aterm
      assert Tailoring.classify(:ja, ?;) == :scontinue
    end
  end

  describe "empty and single-segment inputs" do
    test "line" do
      assert Dfa.Line.next("", :ja) == nil
      assert Dfa.Line.split("", :ja) == []
      assert Dfa.Line.splitter("", :ja) |> Enum.to_list() == []
      assert Dfa.Line.break?("", "x", :ja)
      assert Dfa.Line.break?("x", "", :ja)
    end

    test "sentence" do
      assert Dfa.Sentence.next("", :en, @suppressions) == nil
      assert Dfa.Sentence.split("", :en, @suppressions) == []
      assert Dfa.Sentence.splitter("", :en, @suppressions) |> Enum.to_list() == []
      assert Dfa.Sentence.break?("", "x", :en, @suppressions)
      assert Dfa.Sentence.break?("x", "", :en, @suppressions)
    end
  end

  describe "break? agrees with split for every break type" do
    # A boundary predicate and a split must not disagree about the same position.
    for break <- [:grapheme, :word, :sentence, :line] do
      test "#{break}" do
        text = "Hello Mr. Smith. Do you like café? Yes!"
        segments = Unicode.String.split(text, break: unquote(break), locale: :en)

        assert Enum.join(segments) == text

        segments
        |> Enum.scan(0, fn segment, offset -> offset + byte_size(segment) end)
        |> Enum.drop(-1)
        |> Enum.each(fn offset ->
          before = binary_part(text, 0, offset)
          rest = binary_part(text, offset, byte_size(text) - offset)

          assert Unicode.String.break?({before, rest}, break: unquote(break), locale: :en),
                 "expected a break at byte #{offset} of #{inspect(text)}"
        end)
      end
    end
  end

  describe "streaming matches splitting" do
    for break <- [:grapheme, :word, :sentence, :line] do
      test "#{break}, with and without trim" do
        text = "One two. Three four! "

        for trim <- [false, true] do
          options = [break: unquote(break), locale: :en, trim: trim]

          assert Unicode.String.split(text, options) ==
                   text |> Unicode.String.stream(options) |> Enum.to_list()

          assert Unicode.String.split(text, options) ==
                   text |> Unicode.String.splitter(options) |> Enum.to_list()
        end
      end
    end
  end

  describe "the dispatch layer" do
    test "splitter falls through to the generic clause for word and grapheme" do
      assert Break.splitter("ab cd", :root, :word, []) |> Enum.to_list() == ["ab", " ", "cd"]
      assert Break.splitter("ab", :root, :grapheme, []) |> Enum.to_list() == ["a", "b"]
    end

    test "trim drops whitespace-only segments on the line and sentence paths" do
      assert Break.splitter("a b", :root, :line, trim: true) |> Enum.to_list() == ["a ", "b"]
      assert "x. y." |> Unicode.String.split(break: :sentence, locale: :en, trim: true) != []
    end
  end
end
