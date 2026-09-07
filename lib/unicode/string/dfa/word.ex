defmodule Unicode.String.Dfa.Word do
  @moduledoc """
  Table-driven engine implementing UAX #29 word break.

  Generated from the `WordBreak` state machine tables published in PRI #555.
  See `Unicode.String.Dfa` for the engine and `Unicode.String.Break.Word`
  for the direct-coded implementation retained as a cross-check.
  """
  use Unicode.String.Dfa, type: "WordBreak"
end
