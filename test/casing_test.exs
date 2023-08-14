defmodule UnicodeString.Casing.Test do
  use ExUnit.Case, async: true

  test "Casing greek with final sigma" do
    assert Unicode.String.Case.Mapping.upcase("Ὀδυσσεύς") == "ὈΔΥΣΣΕΎΣ"
    assert Unicode.String.Case.Mapping.titlecase("ὈΔΥΣΣΕΎΣ") == "Ὀδυσσεύς"
    assert Unicode.String.Case.Mapping.downcase("ὈΔΥΣΣΕΎΣ") == "ὀδυσσεύς"
  end

  test "Upcasing i in the Turkish and Azerbaijani locales returns capital dotted-I" do
    assert Unicode.String.Case.Mapping.upcase("ii", :tr) == "İİ"
    assert Unicode.String.Case.Mapping.upcase("ii", :az) == "İİ"
    assert Unicode.String.Case.Mapping.upcase("ii") == "II"
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
