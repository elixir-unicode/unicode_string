defmodule UnicodeString.Segment.Test do
  use ExUnit.Case, async: true

  if Code.ensure_loaded?(Localize.LanguageTag.Sigil) do
    test "Resolving the segmentation locale from a Language Tag" do
      import Localize.LanguageTag.Sigil

      assert Unicode.String.segmentation_locale(:word, ~l"fr") == {:ok, :fr}
      assert Unicode.String.segmentation_locale(:word, ~l"en-US") == {:ok, :en}
      assert Unicode.String.segmentation_locale(:word, ~l"en") == {:ok, :en}
      assert Unicode.String.segmentation_locale(:word, ~l"ar") == {:ok, :root}
      assert Unicode.String.segmentation_locale(:word, ~l"und") == {:ok, :root}
    end

    test "Resolving the segmentation locale from the tag's subtags" do
      import Localize.LanguageTag.Sigil

      # The CLDR locale id names the script, and the dictionary locale is
      # preferred for word breaking.
      assert Unicode.String.segmentation_locale(:line, ~l"zh-TW") == {:ok, :"zh-Hant"}
      assert Unicode.String.segmentation_locale(:word, ~l"zh-TW") == {:ok, :"zh-Hant"}
      assert Unicode.String.segmentation_locale(:word, ~l"zh-HK") == {:ok, :"zh-Hant-HK"}
      assert Unicode.String.segmentation_locale(:line, ~l"zh-HK") == {:ok, :"zh-Hant"}
      assert Unicode.String.segmentation_locale(:line, ~l"pt-BR") == {:ok, :pt}
      assert Unicode.String.dictionary_locale(~l"th-TH") == {:ok, :th}
      assert Unicode.String.dictionary_locale(~l"en") == {:ok, nil}
    end

    test "A parsed tag without a CLDR locale id is validated once" do
      {:ok, parsed} = Localize.LanguageTag.parse("fr")
      assert is_nil(parsed.cldr_locale_id)
      assert Unicode.String.segmentation_locale(:word, parsed) == {:ok, :fr}
    end

    test "Resolving the segmentation locale from a string through Localize" do
      assert Unicode.String.segmentation_locale(:word, "en-US") == {:ok, :en}
      assert Unicode.String.segmentation_locale(:line, "zh-TW") == {:ok, :"zh-Hant"}
      assert Unicode.String.segmentation_locale(:word, "zh-HK") == {:ok, :"zh-Hant-HK"}
      assert Unicode.String.segmentation_locale(:word, :"en-US") == {:ok, :en}
    end
  end

  test "Resolving the segmentation locale from a string" do
    assert Unicode.String.segmentation_locale(:word, "fr") == {:ok, :fr}
    assert Unicode.String.segmentation_locale(:word, "en") == {:ok, :en}
    assert Unicode.String.segmentation_locale(:word, "ar") == {:ok, :root}
    assert Unicode.String.segmentation_locale(:word, "root") == {:ok, :root}
    assert Unicode.String.segmentation_locale(:line, "zh-Hant-HK") == {:ok, :"zh-Hant"}
    assert Unicode.String.segmentation_locale(:word, "zh-Hant-HK") == {:ok, :"zh-Hant-HK"}
    assert Unicode.String.segmentation_locale(:word, "zh_Hant") == {:ok, :"zh-Hant"}
    assert Unicode.String.dictionary_locale("th") == {:ok, :th}
    assert Unicode.String.dictionary_locale("en") == {:ok, nil}
  end

  test "Resolving the segmentation locale from an atom" do
    assert Unicode.String.segmentation_locale(:word, :fr) == {:ok, :fr}
    assert Unicode.String.segmentation_locale(:word, :en) == {:ok, :en}
    assert Unicode.String.segmentation_locale(:word, :ar) == {:ok, :root}
    assert Unicode.String.segmentation_locale(:line, :zh_Hant) == {:ok, :"zh-Hant"}
    assert Unicode.String.segmentation_locale(:word, :"zh-Hant") == {:ok, :"zh-Hant"}
  end

  test "An unknown or invalid locale falls back to the default" do
    assert Unicode.String.segmentation_locale(:word, "xx") == {:ok, :root}
    assert Unicode.String.segmentation_locale(:word, "") == {:ok, :root}
    assert Unicode.String.segmentation_locale(:word, nil) == {:ok, :root}
    assert Unicode.String.segmentation_locale(:word, 42) == {:ok, :root}
    assert Unicode.String.segmentation_locale(:word, %{}) == {:ok, :root}
    assert Unicode.String.segmentation_locale(:word, :"") == {:ok, :root}
    assert Unicode.String.casing_locale("xx") == {:ok, :any}
    assert Unicode.String.dictionary_locale("xx") == {:ok, nil}
  end
end
