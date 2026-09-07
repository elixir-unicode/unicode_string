defmodule Unicode.String.RemainingDoctestTest do
  use ExUnit.Case, async: true

  doctest Unicode.String.Dictionary
  doctest Unicode.String.DictionaryBreak
  doctest Unicode.String.Case.Mapping
end
