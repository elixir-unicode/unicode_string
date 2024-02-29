defmodule Unicode.String.Case.Mapping.Greek do
  @moduledoc """
  Implements the special upper casing rules for
  for the Greek language.

  """

  @remove_accents Unicode.Regex.compile!(
                    "[^[:ccc=Not_Reordered:][:ccc=Above:]]*?[\\u0313\\u0314\\u0301\\u0300\\u0306\\u0342\\u0308\\u0304]"
                  )
  @remove_iota Unicode.Regex.compile!("[^[:ccc=Not_Reordered:][:ccc=Iota_Subscript:]]*?[\\u0345]")

  @doc """
  This implementation currently implements the `el-Upper` transform
  from CLDR.

  ### CLDR algorithm

  According to CLDR all accents on all characters are are omitted when
  upcasing.

    Remove 0301 following Greek, with possible intervening 0308 marks.
    ::NFD();
    For uppercasing (not titlecasing!) remove all greek accents from greek letters.
    This is done in two groups, to account for canonical ordering.
    [:Greek:] [^[:ccc=Not_Reordered:][:ccc=Above:]]*? { [\u0313\u0314\u0301\u0300\u0306\u0342\u0308\u0304] → ;
    [:Greek:] [^[:ccc=Not_Reordered:][:ccc=Iota_Subscript:]]*? { \u0345 → ;
    ::NFC();

  That transform basically says remove all accents except a
  subscripted iota. It doesn't handle dipthongs correctly.

  ### Mozilla algorithm

  Mozilla has a thread on a [bug report](https://bugzilla.mozilla.org/show_bug.cgi?id=307039)
  that:

  >  Greek accented letters should be converted to the respective non-accented uppercase
  >  letters. The required conversions are the following (in Unicode):
  >
  >  ά -> Α
  >  έ -> Ε
  >  ή -> Η
  >  ί -> Ι
  >  ΐ -> Ϊ
  >  ό -> Ο
  >  ύ -> Υ
  >  ΰ -> Ϋ
  >  ώ -> Ω
  >
  >  Also diphthongs (two-vowel constructs) should be converted as follows, when the
  >  first vowel is accented:
  >
  >  άι -> ΑΪ
  >  έι -> ΕΪ
  >  όι -> ΟΪ
  >  ύι -> ΥΪ
  >  άυ -> ΑΫ
  >  έυ -> ΕΫ
  >  ήυ -> ΗΫ
  >  όυ -> ΟΫ

  That thread seems to align with current-day [Mozilla](https://developer.mozilla.org/en-US/docs/Web/CSS/text-transform)
  which says the rules are:

  > In Greek (el), vowels lose their accent when the whole word is in
  > uppercase (ά/Α), except for the disjunctive eta (ή/Ή). Also, diphthongs
  > with an accent on the first vowel lose the accent and gain a diaeresis
  > on the second vowel (άι/ΑΪ).

  """
  def upcase(string) do
    string
    |> String.normalize(:nfd)
    |> String.replace(@remove_accents, "")
    |> String.replace(@remove_iota, "")
    |> String.normalize(:nfc)
    |> Unicode.String.Case.Mapping.upcase(:any)
  end
end
