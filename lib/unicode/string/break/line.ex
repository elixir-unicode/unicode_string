defmodule Unicode.String.Break.Line do
  @moduledoc """
  Deprecated. Use `Unicode.String.Dfa.Line` instead.

  This module implemented the annex by hand. Segmentation is now driven by the
  state machine tables published in PRI #555, and this module delegates to the
  engine generated from them. Its behaviour is unchanged; only the module name
  has moved.

  Neither module is the supported interface. `Unicode.String` is the API to
  prefer, and it is unaffected by this change.
  """

  alias Unicode.String.Dfa

  @doc "Returns `{segment, rest}`, or `nil` when `string` is empty."
  @deprecated "Use Unicode.String.Dfa.Line.next/1 instead"
  defdelegate next(string), to: Dfa.Line

  @doc "Splits `string` into segments."
  @deprecated "Use Unicode.String.Dfa.Line.rule_split/1 instead"
  defdelegate split(string), to: Dfa.Line, as: :rule_split

  @doc "Returns `true` when a boundary falls between the two strings."
  @deprecated "Use Unicode.String.Dfa.Line.break?/2 instead"
  defdelegate break?(string_before, string_after), to: Dfa.Line
end
