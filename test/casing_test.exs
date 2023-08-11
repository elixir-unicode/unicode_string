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
end
