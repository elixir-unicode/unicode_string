defmodule Unicode.String.SegmentApiTest do
  use ExUnit.Case, async: true

  alias Unicode.String.Segment

  @segment_types [:grapheme_cluster_break, :word_break, :sentence_break, :line_break]

  describe "locale metadata" do
    test "known_segmentation_locales/0 includes the root and common locales" do
      locales = Segment.known_segmentation_locales()
      assert :root in locales
      assert :en in locales
    end

    test "locale_map/0 maps locale names to segment files" do
      map = Segment.locale_map()
      assert is_map(map)
      assert Map.has_key?(map, "en")
    end

    test "segments_dir/0 returns the priv segments directory" do
      dir = Segment.segments_dir()
      assert File.dir?(dir)
      assert Path.basename(dir) == "segments"
    end
  end

  describe "ancestors/1 and merge_ancestors/1" do
    test "the root locale resolves to root" do
      assert {:ok, ancestors} = Segment.ancestors("root")
      assert Enum.uniq(ancestors) == ["root"]
    end

    test "a base locale falls back to root" do
      assert Segment.ancestors("en") == {:ok, ["en", "root"]}
    end

    test "a sublocale walks up through its parents to root" do
      assert Segment.ancestors("en-US") == {:ok, ["en-US", "en", "root"]}
    end

    test "merge_ancestors/1 returns a merged segment map" do
      assert {:ok, segments} = Segment.merge_ancestors("en")
      assert Map.has_key?(segments, :word_break)
    end
  end

  describe "segments/1,2" do
    test "segments/1 accepts a string locale" do
      assert {:ok, segments} = Segment.segments("en")
      assert Enum.sort(Map.keys(segments)) == Enum.sort(@segment_types)
    end

    test "segments/1 accepts an atom locale" do
      assert {:ok, _segments} = Segment.segments(:en)
    end

    test "segments/1 returns an error for an unknown locale" do
      assert {:error, message} = Segment.segments("xx-nope")
      assert message =~ "Unknown locale"
    end

    test "segments/2 returns a single segment definition" do
      assert {:ok, segment} = Segment.segments("en", :word_break)
      assert Map.has_key?(segment, :rules)
      assert Map.has_key?(segment, :variables)
    end

    test "segments/2 returns an error for an unknown segment type" do
      assert {:error, message} = Segment.segments("en", :not_a_type)
      assert message =~ "Unknown segment type"
    end
  end

  describe "rules/2,3 and rules!/2" do
    test "rules/2 compiles the rule set for every segment type" do
      for type <- @segment_types do
        assert {:ok, rules} = Segment.rules("en", type)
        assert is_list(rules)
        assert rules != []
      end
    end

    test "rules/3 accepts additional variables" do
      assert {:ok, rules} = Segment.rules("en", :word_break, [])
      assert is_list(rules)
    end

    test "rules!/2 returns the list directly" do
      assert is_list(Segment.rules!("en", :sentence_break))
    end

    test "rules!/2 raises for an unknown segment type" do
      assert_raise ArgumentError, fn -> Segment.rules!("en", :not_a_type) end
    end
  end

  describe "suppressions/2 and suppressions!/2" do
    test "suppressions/2 returns a list" do
      assert {:ok, suppressions} = Segment.suppressions("en", :sentence_break)
      assert is_list(suppressions)
    end

    test "suppressions!/2 returns the list directly" do
      assert is_list(Segment.suppressions!("en", :sentence_break))
    end

    test "suppressions!/2 raises for an unknown segment type" do
      assert_raise ArgumentError, fn -> Segment.suppressions!("en", :not_a_type) end
    end
  end

  describe "compile_rule/2 and evaluate_rules/2" do
    test "compile_rule/2 compiles a single rule map" do
      variables = %{"L" => "\\p{L}"}

      assert {1.0, {operator, _fore, _aft}} =
               Segment.compile_rule(%{id: 1.0, value: "$L × $L"}, variables)

      assert operator == :no_break
    end

    test "evaluate_rules/2 returns a break decision for each segment type" do
      for type <- @segment_types do
        {:ok, rules} = Segment.rules("en", type)

        for string <- ["Hello world.", "a", "Mr. Smith left. He ran.", ""] do
          assert {operator, _match} = Segment.evaluate_rules(string, rules)
          assert operator in [:break, :no_break]
        end
      end
    end

    test "evaluate_rules/2 accepts a {before, after} tuple" do
      {:ok, rules} = Segment.rules("en", :sentence_break)
      assert {operator, _match} = Segment.evaluate_rules({"Hello", " world."}, rules)
      assert operator in [:break, :no_break]
    end
  end

  describe "error helpers" do
    test "unknown_locale_error/1" do
      assert Segment.unknown_locale_error("zz") =~ "Unknown locale"
    end

    test "unknown_segment_type_error/1" do
      assert Segment.unknown_segment_type_error(:zz) =~ "Unknown segment type"
    end
  end

  describe "Unicode.String.word_like?/1" do
    test "letters, digits, and letter-punctuation combinations are word-like" do
      assert Unicode.String.word_like?("sentence")
      assert Unicode.String.word_like?("can't")
      assert Unicode.String.word_like?("123")
      assert Unicode.String.word_like?("١٢٣")
      assert Unicode.String.word_like?("中文")
      assert Unicode.String.word_like?("カタカナ")
    end

    test "white space, punctuation, and symbols are not word-like" do
      refute Unicode.String.word_like?(" ")
      refute Unicode.String.word_like?(".")
      refute Unicode.String.word_like?("_")
      refute Unicode.String.word_like?("—")
      refute Unicode.String.word_like?("")
    end

    test "classifies word segments per the JS Intl.Segmenter isWordLike property" do
      classified =
        "Hello, 世界! 42."
        |> Unicode.String.split(break: :word)
        |> Enum.map(&{&1, Unicode.String.word_like?(&1)})

      assert {"Hello", true} in classified
      assert {",", false} in classified
      assert {"42", true} in classified
      assert {"世界", true} in classified or {"世", true} in classified
    end
  end
end
