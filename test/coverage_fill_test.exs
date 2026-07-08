defmodule Unicode.String.CoverageFillTest do
  use ExUnit.Case, async: true

  alias Unicode.String
  alias Unicode.String.Case.Folding
  alias Unicode.String.Case.Mapping
  alias Unicode.String.Dictionary

  describe "case folding variants" do
    test "fold/1 applies full folding" do
      assert Folding.fold("Weiß") == "weiss"
    end

    test "fold/2 with the :turkic atom folds the dotted capital I" do
      assert Folding.fold("İ", :turkic) == "i"
    end

    test "fold/2 with a turkic language tag map" do
      assert Folding.fold("İ", %{language: :tr}) == "i"
      assert Folding.fold("İ", :az) == "i"
    end

    test "fold/2 with a non-turkic language tag map" do
      assert Folding.fold("Weiß", %{language: :en}) == "weiss"
    end

    test "fold/2 through the Unicode.String delegate" do
      assert String.fold("Weiß") == "weiss"
      assert String.fold("İ", :turkic) == "i"
    end
  end

  describe "locale-aware case mapping contexts" do
    test "a non-final sigma lowercases to a medial sigma" do
      assert Mapping.downcase("ΣΑ") == "σα"
    end

    test "Lithuanian lowercasing adds an explicit dot above (More_Above)" do
      input = "I" <> <<0x0300::utf8>>
      assert Mapping.downcase(input, :lt) == <<0x69, 0x0307::utf8, 0x0300::utf8>>
      # Differs from the locale-independent mapping, proving the lt rule ran.
      refute Mapping.downcase(input, :lt) == Mapping.downcase(input)
    end

    test "Lithuanian uppercasing keeps the dot above after a soft-dotted i" do
      input = "i" <> <<0x0307::utf8>>
      assert Mapping.upcase(input, :lt) == <<0x49, 0x0307::utf8>>
    end

    test "Turkish lowercasing of I before a dot above yields a dotless i" do
      input = "I" <> <<0x0307::utf8>>
      assert Mapping.downcase(input, :tr) == <<0x0131::utf8, 0x0307::utf8>>
    end

    test "ASCII punctuation and digits pass through the fast path" do
      assert Mapping.upcase("123 xyz!") == "123 XYZ!"
      assert Mapping.downcase("123!ABC") == "123!abc"
    end

    test "Turkish I preceded by a dot above keeps its dot (Before_Dot)" do
      input = <<0x0307::utf8, ?I::utf8>>
      assert Mapping.downcase(input, :tr) == <<0x0307::utf8, ?i::utf8>>
    end

    test "Lithuanian uppercasing retains a following combining accent" do
      input = <<?i::utf8, 0x0307::utf8, 0x0300::utf8>>
      assert Mapping.upcase(input, :lt) == <<?I::utf8, 0x0307::utf8, 0x0300::utf8>>
    end

    test "unknown_locale_error/1 formats the locale" do
      assert Mapping.unknown_locale_error(:xx) == "Unknown locale :xx"
    end
  end

  describe "dictionary lookups" do
    setup do
      Dictionary.load(:th)
      Dictionary.load(:ja)
      :ok
    end

    test "known_dictionary_locales/0 lists the dictionary locales" do
      locales = Dictionary.known_dictionary_locales()
      assert :th in locales
      assert :ja in locales
    end

    test "loaded?/1 reflects whether a dictionary is present" do
      assert Dictionary.loaded?(:th)
      refute Dictionary.loaded?(:invalid_locale)
    end

    test "the Japanese dictionary aliases the shared CJK dictionary" do
      assert Dictionary.loaded?(:ja)
    end

    test "has_key/2 finds a word in the loaded dictionary" do
      assert Dictionary.has_key("ประเทศ", :th)
    end

    test "dictionary_locale/1 resolves language tag maps and unknown locales" do
      assert Dictionary.dictionary_locale(%{language: :th}) == {:ok, :th}
      assert {:error, message} = Dictionary.dictionary_locale(:xx)
      assert message =~ "No dictionary"
    end
  end
end
