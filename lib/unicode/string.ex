defmodule Unicode.String do

  alias Unicode.String.Segment
  alias Unicode.String.Break

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

  @default_locale "root"

  def split(string, options \\ []) when is_binary(string) do
    locale = Keyword.get(options, :locale, @default_locale)
    break = Keyword.get(options, :break, :word)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- validate(:locale, locale) do
      Break.break(string, locale, break, options)
    end
    |> maybe_trim(options[:trim])
  end

  defp maybe_trim(list, true) do
    Enum.reject(list, &Unicode.Property.white_space?/1)
  end

  defp maybe_trim(list, _) do
    list
  end

  defp validate(:locale, locale) do
    if locale in Segment.locales() do
      {:ok, locale}
    else
      {:error, Segment.unknown_locale_error(locale)}
    end
  end

  @breaks [:word, :grapheme, :line, :sentence]

  defp validate(:break, break) do
    if break in @breaks do
      {:ok, break}
    else
      {:error, "Unknown break #{inspect break}. Valid breaks are #{inspect @breaks}"}
    end
  end

end
