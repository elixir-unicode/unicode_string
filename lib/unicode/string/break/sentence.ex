defmodule Unicode.String.Break.Sentence do
  @moduledoc """
  Deprecated. Use `Unicode.String.Dfa.Sentence` instead. This module is removed
  in 2.5.0.

  This module implemented UAX #29 sentence breaking by hand. Segmentation is now
  driven by the state machine tables published in PRI #555, and this module
  delegates to the engine generated from them. Its behaviour is unchanged; only
  the module name has moved.

  Neither module is the supported interface. `Unicode.String` is the API to
  prefer, and it is unaffected by this change.
  """

  alias Unicode.String.Dfa

  @doc "Returns `{sentence, rest}`, or `nil` when `string` is empty."
  @deprecated "Use Unicode.String.Dfa.Sentence.next/3 instead. Removed in 2.5.0"
  defdelegate next(string, locale, suppressions), to: Dfa.Sentence

  @doc "Splits `string` into sentences under `locale`."
  @deprecated "Use Unicode.String.Dfa.Sentence.split/3 instead. Removed in 2.5.0"
  defdelegate split(string, locale, suppressions), to: Dfa.Sentence

  @doc "Returns `true` when a sentence boundary falls between the two strings."
  @deprecated "Use Unicode.String.Dfa.Sentence.break?/4 instead. Removed in 2.5.0"
  defdelegate break?(string_before, string_after, locale, suppressions), to: Dfa.Sentence
end
