defmodule UnicodeString.Segment.Test do
  use ExUnit.Case, async: true

  test "Resolving the segmentation locale from a Language Tag" do
    import Cldr.LanguageTag.Sigil

    assert Unicode.String.segmentation_locale(:word, ~l"fr") == {:ok, :fr}
    assert Unicode.String.segmentation_locale(:word, ~l"en-US") == {:ok, :"en-US"}
    assert Unicode.String.segmentation_locale(:word, ~l"en") == {:ok, :en}
    assert Unicode.String.segmentation_locale(:word, ~l"ar") == {:ok, :root}
  end

  test "Resolving the segmentation locale from a string" do
    assert Unicode.String.segmentation_locale(:word, "fr") == {:ok, :fr}
    assert Unicode.String.segmentation_locale(:word, "en-US") == {:ok, :"en-US"}
    assert Unicode.String.segmentation_locale(:word, "en") == {:ok, :en}
    assert Unicode.String.segmentation_locale(:word, "ar") == {:ok, :root}
  end

  test "Resolving the segmentation locale from an atom" do
    assert Unicode.String.segmentation_locale(:word, :fr) == {:ok, :fr}
    assert Unicode.String.segmentation_locale(:word, :"en-US") == {:ok, :"en-US"}
    assert Unicode.String.segmentation_locale(:word, :en) == {:ok, :en}
    assert Unicode.String.segmentation_locale(:word, :ar) == {:ok, :root}
  end
end
