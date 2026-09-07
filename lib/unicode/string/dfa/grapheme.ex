defmodule Unicode.String.Dfa.Grapheme do
  @moduledoc """
  Table-driven engine implementing UAX #29 grapheme cluster segmentation.

  Generated from the `GraphemeClusterBreak` state machine tables published in
  PRI #555. See `Unicode.String.Dfa` for the engine.
  """
  use Unicode.String.Dfa, type: "GraphemeClusterBreak"
end
