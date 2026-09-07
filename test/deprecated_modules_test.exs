defmodule Unicode.String.DeprecatedModulesTest do
  use ExUnit.Case, async: true

  alias Unicode.String.Break
  alias Unicode.String.Dfa

  # These modules are deprecated shims over the generated engines. They are
  # called through `apply/3` so that compiling this file does not emit the
  # deprecation warning they exist to produce.
  defp call(module, function, arguments), do: apply(module, function, arguments)

  @text "Hello there. Mr. Smith went to Ph.D. school in café Zürich!"
  @none MapSet.new()

  describe "the deprecated modules delegate without changing behaviour" do
    test "grapheme" do
      assert call(Break.Grapheme, :split, [@text]) == Dfa.Grapheme.split(@text)
      assert call(Break.Grapheme, :next, [@text]) == Dfa.Grapheme.next(@text)
      assert call(Break.Grapheme, :break?, ["ab", "c"]) == Dfa.Grapheme.break?("ab", "c")
    end

    test "word" do
      assert call(Break.Word, :split, [@text]) == Dfa.Word.split(@text)
      assert call(Break.Word, :next, [@text]) == Dfa.Word.next(@text)
      assert call(Break.Word, :break?, ["ab", " c"]) == Dfa.Word.break?("ab", " c")
    end

    test "line delegates to the rules alone, without the dictionary pass" do
      assert call(Break.Line, :split, [@text]) == Dfa.Line.rule_split(@text)
      assert call(Break.Line, :next, [@text]) == Dfa.Line.next(@text)
      assert call(Break.Line, :break?, ["a ", "b"]) == Dfa.Line.break?("a ", "b")
    end

    test "sentence" do
      assert call(Break.Sentence, :split, [@text, :en, @none]) ==
               Dfa.Sentence.split(@text, :en, @none)

      assert call(Break.Sentence, :next, [@text, :en, @none]) ==
               Dfa.Sentence.next(@text, :en, @none)

      assert call(Break.Sentence, :break?, ["One.", " Two", :en, @none]) ==
               Dfa.Sentence.break?("One.", " Two", :en, @none)
    end
  end

  describe "the deprecations are declared" do
    test "every delegated function carries a deprecation notice" do
      expected = [
        {Break.Grapheme, [next: 1, split: 1, break?: 2]},
        {Break.Word, [next: 1, split: 1, break?: 2]},
        {Break.Line, [next: 1, split: 1, break?: 2]},
        {Break.Sentence, [next: 3, split: 3, break?: 4]}
      ]

      for {module, functions} <- expected do
        {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

        deprecated =
          for {{:function, name, arity}, _, _, _, metadata} <- docs,
              Map.has_key?(metadata, :deprecated),
              do: {name, arity}

        assert Enum.sort(deprecated) == Enum.sort(functions),
               "#{inspect(module)} deprecations do not match its public functions"
      end
    end
  end
end
