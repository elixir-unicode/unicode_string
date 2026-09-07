defmodule Unicode.String.ExtendedPictographic do
  @moduledoc """
  A guard-safe test for the `Extended_Pictographic` property.

  The property is consulted once per codepoint by the grapheme break rules
  (GB11) and the line break rules (LB30b), so it sits in the hot path of both.

  Testing its 156 ranges as a flat chain of `or` comparisons costs all 156 for
  every character that is *not* pictographic, because `or` short-circuits on
  true rather than on false, and in ordinary text almost no character is
  pictographic. The first range begins at U+00A9, which makes Latin text the
  worst case rather than the best one.

  The ranges are therefore compiled into a balanced binary tree of comparisons
  instead. Each node tests one range and descends into one side:

      (codepoint < from and <left>) or
      (codepoint > to and <right>) or
      (codepoint >= from and codepoint <= to)

  `and` and `or` are short-circuiting, so exactly one subtree is evaluated and
  the depth is log2(156), about 8 nodes. The whole expression is built from
  comparisons and boolean operators only, so it remains valid in a guard.
  """

  @ranges Map.fetch!(Unicode.Emoji.emoji(), :extended_pictographic) |> Enum.sort()

  codepoint = Macro.var(:codepoint, nil)

  build = fn
    _build, [], _var ->
      false

    build, ranges, var ->
      {left, [{from, to} | right]} = Enum.split(ranges, div(length(ranges), 2))

      quote do
        (unquote(var) < unquote(from) and unquote(build.(build, left, var))) or
          (unquote(var) > unquote(to) and unquote(build.(build, right, var))) or
          (unquote(var) >= unquote(from) and unquote(var) <= unquote(to))
      end
  end

  @doc false
  defguard is_extended_pictographic(codepoint)
           when unquote(build.(build, @ranges, codepoint))
end
