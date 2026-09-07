defmodule Unicode.String.CaseMappingConformanceTest do
  use ExUnit.Case, async: true

  alias Unicode.String.Case.Mapping

  # `Unicode.String.Case.Mapping` generates one function clause per entry in the
  # Unicode special casing data, so the only way to exercise it is to drive it
  # from the same data. Entries carrying a context (`final_sigma`, `after_i` and
  # the rest) need surrounding text to trigger and are covered separately below.
  @entries Enum.filter(Unicode.Utils.casing_in_order(), &(&1[:context] == nil))

  defp mismatches(key, fun) do
    @entries
    |> Enum.filter(&(&1[key] != nil))
    |> Enum.reject(fn entry ->
      fun.(<<entry.codepoint::utf8>>, entry.language) ==
        :unicode.characters_to_binary(entry[key])
    end)
    |> Enum.map(fn entry ->
      {"U+" <> Integer.to_string(entry.codepoint, 16), entry.language}
    end)
  end

  test "every uncontextual upper case mapping" do
    assert mismatches(:upper, &Mapping.upcase/2) == []
  end

  test "every uncontextual lower case mapping" do
    assert mismatches(:lower, &Mapping.downcase/2) == []
  end

  test "every uncontextual title case mapping" do
    assert mismatches(:title, &Mapping.titlecase/2) == []
  end

  test "the data covers every special casing language" do
    languages = @entries |> Enum.map(& &1.language) |> Enum.uniq() |> Enum.sort()
    assert languages == [:any, :az, :lt, :tr]
  end

  describe "context-dependent casing" do
    test "final sigma takes its word-final form" do
      # Sigma lower cases to ς at the end of a word and σ elsewhere.
      assert Mapping.downcase("ΟΣ") == "ος"
      assert Mapping.downcase("ΣΟΣ") == "σος"
      assert Mapping.downcase("ὈΔΥΣΣΕΎΣ", :el) == "ὀδυσσεύς"
    end

    test "Turkish and Azeri keep the dot on i when upper casing" do
      for locale <- [:tr, :az] do
        assert Mapping.upcase("i", locale) == "İ"
        assert Mapping.downcase("I", locale) == "ı"
        assert Mapping.downcase("İ", locale) == "i"
      end
    end

    test "Lithuanian retains the dot above i under an accent" do
      # U+0307 COMBINING DOT ABOVE is kept when lower casing a dotted capital.
      assert Mapping.downcase("Į", :lt) =~ "į"
      assert Mapping.upcase("į", :lt) == "Į"
    end

    test "more_above adds the dot when an above-accent follows" do
      grave = <<0x0300::utf8>>
      dot = <<0x0307::utf8>>

      assert Mapping.downcase("I" <> grave, :lt) == "i" <> dot <> grave
      assert Mapping.downcase(<<0x012E::utf8>> <> grave, :lt) == <<0x012F::utf8>> <> dot <> grave

      # With nothing above following, the plain mapping applies.
      assert Mapping.downcase("I", :lt) == "i"
    end

    test "before_dot is a lookahead, not a lookbehind" do
      # Turkish and Azeri lower case I to dotless ı, but not when a combining
      # dot above follows: there the dot is already carried by the sequence.
      dot = <<0x0307::utf8>>

      for locale <- [:tr, :az] do
        assert Mapping.downcase("I", locale) == "ı"
        assert Mapping.downcase("I" <> dot, locale) == "i" <> dot
      end

      assert Mapping.downcase("DIYARBAKIR", :tr) == "dıyarbakır"
    end

    test "a context that does not apply does not duplicate the prefix" do
      # The fallback path re-cases one character with the default rules. It must
      # start from an empty accumulator, or everything mapped so far is folded
      # into the result and then emitted twice.
      dot = <<0x0307::utf8>>

      assert Mapping.upcase("i" <> dot, :tr) == <<0x0130::utf8>> <> dot
      assert Mapping.downcase("i" <> dot, :lt) == "i" <> dot
    end

    test "Greek removes accents when upper casing" do
      assert Mapping.upcase("Πατάτα, Αέρας, Μυστήριο", :el) == "ΠΑΤΑΤΑ, ΑΕΡΑΣ, ΜΥΣΤΗΡΙΟ"
      assert Mapping.upcase("ά", :el) == "Α"
    end

    test "Dutch title cases the ij digraph as a unit" do
      assert Mapping.titlecase("ijsselmeer", :nl) == "IJsselmeer"
      assert Mapping.titlecase("Ijsselmeer", :nl) == "IJsselmeer"
    end
  end
end
