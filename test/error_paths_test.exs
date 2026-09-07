defmodule Unicode.String.ErrorPathsTest do
  use ExUnit.Case, async: true

  alias Unicode.String.Break.Tailoring
  alias Unicode.String.Segment

  @suppressions MapSet.new(["mr"])

  describe "suppression matching on degenerate segments" do
    test "a segment that is entirely trailing context suppresses nothing" do
      # `drop_tail/2` consumes spaces, closes and separators looking for the
      # ATerm. If it consumes everything there is no ATerm and no suppression.
      for segment <- ["   ", "\n", ")  ", ""] do
        refute Tailoring.suppressed?(segment, :en, @suppressions)
      end
    end

    test "an ATerm with no word before it suppresses nothing" do
      refute Tailoring.suppressed?(".", :en, @suppressions)
      refute Tailoring.suppressed?(" .", :en, @suppressions)
    end

    test "a word not in the set suppresses nothing" do
      refute Tailoring.suppressed?("Hello Xyz.", :en, @suppressions)
    end

    test "matching is case insensitive" do
      assert Tailoring.suppressed?("Hello MR.", :en, @suppressions)
      assert Tailoring.suppressed?("Hello mr.", :en, @suppressions)
    end

    test "the Greek tailoring reaches classify for both codepoints" do
      assert Tailoring.classify(:el, 0x003B) == :sterm
      assert Tailoring.classify(:el, 0x037E) == :sterm
      assert Tailoring.classify(:en, 0x037E) != :sterm
    end
  end

  describe "segment data errors are returned, not raised" do
    test "rules/3 and suppressions/2 return an error tuple for an unknown locale" do
      assert {:error, _} = Segment.rules(:xx, :sentence_break)
      assert {:error, _} = Segment.suppressions(:xx, :sentence_break)
      assert {:error, _} = Segment.ancestors("xx")
    end

    test "rules/3 returns an error for an unknown segment type" do
      assert {:error, _} = Segment.rules(:en, :not_a_break)
    end

    test "the bang variants raise on the same input" do
      assert_raise ArgumentError, fn -> Segment.rules!(:xx, :sentence_break) end
      assert_raise ArgumentError, fn -> Segment.suppressions!(:xx, :sentence_break) end
    end
  end

  describe "rule evaluation" do
    test "reports a break and a no-break" do
      {:ok, rules} = Segment.rules(:en, :sentence_break)

      assert {:no_break, _} = Segment.evaluate_rules("Hello there.", rules)
      assert {operator, _} = Segment.evaluate_rules({"Hello there.", " Next"}, rules)
      assert operator in [:break, :no_break]
    end

    test "evaluating against an empty remainder terminates" do
      {:ok, rules} = Segment.rules(:en, :sentence_break)
      assert {_operator, _} = Segment.evaluate_rules({"Hello.", ""}, rules)
    end
  end
end
