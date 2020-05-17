defmodule Unicode.String do

  defdelegate fold(string), to: Unicode.String.Case.Folding
  defdelegate fold(string, type), to: Unicode.String.Case.Folding

  @doc """
  Compares two strings in a case insensitive
  manner.

  Case folding is applied to the two string
  arguments which are then compared with the
  `==` operator.

  ## Arguments

  * `string_a` and `string_b` are two strings
    to be compared

  * `type` is the case folding type to be
    applied. The alternatives are `:full`,
    `:simple` and `:turkic`.  The default is
    `:full`.

  ## Returns

  * `true` or `false`

  ## Notes

  * This function applies the [Unicode Case Folding
    algorithm](https://www.unicode.org/versions/Unicode13.0.0/ch03.pdf)

  * The algorithm does not apply any treatment to diacritical
    marks hence "compare strings without accents" is not
    part of this function.

  ## Examples

      iex> Unicode.String.equals_ignoring_case? "ABC", "abc"
      true

      iex> Unicode.String.equals_ignoring_case? "beißen", "beissen"
      true

      iex> Unicode.String.equals_ignoring_case? "grüßen", "grussen"
      false

  """
  def equals_ignoring_case?(string_a, string_b, type \\ :full) do
    fold(string_a, type) == fold(string_b, type)
  end

end
