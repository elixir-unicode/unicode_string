defmodule Unicode.String.GuidesTest do
  use ExUnit.Case, async: true

  doctest_file("guides/introduction.md")
  doctest_file("guides/grapheme_break.md")
  doctest_file("guides/word_break.md")
  doctest_file("guides/sentence_break.md")
  doctest_file("guides/line_break.md")
  doctest_file("guides/casing.md")
end
