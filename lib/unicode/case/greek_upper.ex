defmodule Unicode.String.Case.Mapping.Greek do
  @moduledoc false

  # Uses the CLDR transform for el-Upper
  # Copyright (C) 2011-2013, Apple Inc. and others. All Rights Reserved.
  # Remove \0301 following Greek, with possible intervening 0308 marks.
  # ::NFD();
  # For uppercasing (not titlecasing!) remove all greek accents from greek letters.
  # This is done in two groups, to account for canonical ordering.
  # [:Greek:] [^[:ccc=Not_Reordered:][:ccc=Above:]]*? { [\u0313\u0314\u0301\u0300\u0306\u0342\u0308\u0304] → ;
  # [:Greek:] [^[:ccc=Not_Reordered:][:ccc=Iota_Subscript:]]*? { \u0345 → ;
  # ::NFC();

  # Greek upcasing: https://bugzilla.mozilla.org/show_bug.cgi?id=307039

  @remove_accents Unicode.Regex.compile!("[^[:ccc=Not_Reordered:][:ccc=Above:]]*?[\\u0313\\u0314\\u0301\\u0300\\u0306\\u0342\\u0308\\u0304]*")
  @remove_iota Unicode.Regex.compile!("[^[:ccc=Not_Reordered:][:ccc=Iota_Subscript:]]*?[\\u0345]*")

  def upcase(string) do
    string
    |> String.normalize(:nfd)
    |> String.replace(@remove_accents, "")
    |> String.replace(@remove_iota, "")
    |> Unicode.String.Case.Mapping.upcase(:any)
  end
end