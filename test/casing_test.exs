defmodule UnicodeString.Casing.Test do
  use ExUnit.Case, async: true

  test "Casing Greek with final sigma" do
    assert Unicode.String.Case.Mapping.upcase("Ὀδυσσεύς") == "ὈΔΥΣΣΕΎΣ"
    assert Unicode.String.Case.Mapping.titlecase("ὈΔΥΣΣΕΎΣ") == "Ὀδυσσεύς"
    assert Unicode.String.Case.Mapping.downcase("ὈΔΥΣΣΕΎΣ") == "ὀδυσσεύς"
  end

  test "That accents are removed when upcasing Greek" do
    string = "Πατάτα, Αέρας, Μυστήριο, Ωραίο, Μαΐου, Πόρος, Ρύθμιση, ΰ, Τηρώ, Μάιος, άυλο"
    upcased = "ΠΑΤΑΤΑ, ΑΕΡΑΣ, ΜΥΣΤΗΡΙΟ, ΩΡΑΙΟ, ΜΑΙΟΥ, ΠΟΡΟΣ, ΡΥΘΜΙΣΗ, Υ, ΤΗΡΩ, ΜΑΙΟΣ, ΑΥΛΟ"
    assert Unicode.String.upcase(string, locale: :el) == upcased
  end

  test "Casing dottied I in the Turkish and Azeri languages" do
    assert Unicode.String.Case.Mapping.upcase("ii", :tr) == "İİ"
    assert Unicode.String.Case.Mapping.upcase("ii", :az) == "İİ"
    assert Unicode.String.Case.Mapping.upcase("ii") == "II"
    assert Unicode.String.upcase("Diyarbakır", locale: :tr) == "DİYARBAKIR"
    assert Unicode.String.downcase("DİYARBAKIR", locale: :tr) == "diyarbakır"
  end

  test "Titlecasing in Dutch for leading `ij` dipthong" do
    assert Unicode.String.Case.Mapping.titlecase("ijthings", :nl) == "IJthings"
  end

  test "Resolving the casing locale from a Language Tag" do
    import Cldr.LanguageTag.Sigil

    assert Unicode.String.casing_locale(~l"az") == {:ok, :az}
    assert Unicode.String.casing_locale(~l"tr") == {:ok, :tr}
    assert Unicode.String.casing_locale(~l"lt") == {:ok, :lt}
    assert Unicode.String.casing_locale(~l"en") == {:ok, :any}
    assert Unicode.String.casing_locale(~l"ar") == {:ok, :any}
  end

  test "Resolving the casing locale from a string" do
    assert Unicode.String.casing_locale("az") == {:ok, :az}
    assert Unicode.String.casing_locale("tr") == {:ok, :tr}
    assert Unicode.String.casing_locale("lt") == {:ok, :lt}
    assert Unicode.String.casing_locale("en") == {:ok, :any}
    assert Unicode.String.casing_locale("ar") == {:ok, :any}
  end

  test "Resolving the casing locale from an atom" do
    assert Unicode.String.casing_locale(:az) == {:ok, :az}
    assert Unicode.String.casing_locale(:tr) == {:ok, :tr}
    assert Unicode.String.casing_locale(:lt) == {:ok, :lt}
    assert Unicode.String.casing_locale(:en) == {:ok, :any}
    assert Unicode.String.casing_locale(:ar) == {:ok, :any}
  end
end
