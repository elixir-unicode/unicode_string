defmodule Unicode.String.Break.Grapheme do
  @moduledoc """
  Deprecated. Use `Unicode.String.Dfa.Grapheme` instead.

  This module implemented the annex by hand. Segmentation is now driven by the
  state machine tables published in PRI #555, and this module delegates to the
  engine generated from them. Its behaviour is unchanged; only the module name
  has moved.

  Neither module is the supported interface. `Unicode.String` is the API to
  prefer, and it is unaffected by this change.
  """

  alias Unicode.String.Dfa

  @doc "Returns `{segment, rest}`, or `nil` when `string` is empty."
  @deprecated "Use Unicode.String.Dfa.Grapheme.next/1 instead"
  defdelegate next(string), to: Dfa.Grapheme

  @doc "Splits `string` into segments."
  @deprecated "Use Unicode.String.Dfa.Grapheme.split/1 instead"
  defdelegate split(string), to: Dfa.Grapheme, as: :split

  @doc "Returns `true` when a boundary falls between the two strings."
  @deprecated "Use Unicode.String.Dfa.Grapheme.break?/2 instead"
  defdelegate break?(string_before, string_after), to: Dfa.Grapheme
end
