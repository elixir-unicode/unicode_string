defmodule Unicode.String do
  @moduledoc """
  Elixir provides native support for UTF-8 string
  providing a firm foundation for manipulating strings
  in multiple scripts.

  The functions in this module complement the
  functions in the `String` module.

  """

  alias Unicode.String.Segment
  alias Unicode.String.Break
  alias Unicode.Property

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

  @doc """
  Returns a boolean indicating if the
  requested break is applicable
  at the point between the two string
  segments represented by `{string_before, string_after}`.

  ## Arguments

  * `string` is any `String.t`.

  * `options` is a keyword list of
    options.

  ## Returns

  * `true` or `false`

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_locales/0`.
    The default is "root" which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `:word`.

  * `:suppressions` is a boolean which,
    if `true`, will suppress breaks for common
    abbreviations defined for the `locale`. The
    default is `true`.

  ## Examples

      iex> Unicode.String.break? {"This is ", "some words"}
      true

      iex> Unicode.String.break? {"This is ", "some words"}, break: :sentence
      false

      iex> Unicode.String.break? {"This is one. ", "This is some words."}, break: :sentence
      true

  """
  def break?({string_before, string_after}, options \\ []) do
    case break({string_before, string_after}, options) do
      {:break, _} -> true
      {:no_break, _} -> false
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Returns match data indicating if the
  requested break is applicable
  at the point between the two string
  segments represented by `{string_before, string_after}`.

  ## Arguments

  * `string` is any `String.t`.

  * `options` is a keyword list of
    options.

  ## Returns

  A tuple indicating if a break would
  be applicable at this point between
  `string_before` and `string_after`.

  * `{:break, {string_before, [matched_string, remaining_string]}}` or

  * `{:no_break, {string_before, [matched_string, remaining_string]}}`

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_locales/0`.
    The default is "root" which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `:word`.

  * `:suppressions` is a boolean which,
    if `true`, will suppress breaks for common
    abbreviations defined for the `locale`. The
    default is `true`.

  ## Examples

      iex> Unicode.String.break {"This is ", "some words"}
      {:break, {"This is ", ["s", "ome words"]}}

      iex> Unicode.String.break {"This is ", "some words"}, break: :sentence
      {:no_break, {"This is ", ["s", "ome words"]}}

      iex> Unicode.String.break {"This is one. ", "This is some words."}, break: :sentence
      {:break, {"This is one. ", ["T", "his is some words."]}}

  """
  def break({string_before, string_after}, options \\ []) do
    locale = Keyword.get(options, :locale, @default_locale)
    break = Keyword.get(options, :break, :word)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- validate(:locale, locale) do
      Break.break({string_before, string_after}, locale, break, options)
    end
  end

  @doc """
  Returns an enumerable that splits a string on demand.

  ## Arguments

  * `string` is any `String.t`.

  * `options` is a keyword list of
    options.

  ## Returns

  A function that implements the enumerable
  protocol.

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_locales/0`.
    The default is "root" which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `:word`.

  * `:suppressions` is a boolean which,
    if `true`, will suppress breaks for common
    abbreviations defined for the `locale`. The
    default is `true`.

  * `:trim` is a boolean indicating if segments
    the are comprised of only white space are to be
    excluded fromt the returned list.  The default
    is `false`.

  ## Examples

      iex> enum = Unicode.String.splitter "This is a sentence. And another.", break: :word, trim: true
      iex> Enum.take enum, 3
      ["This", "is", "a"]

  """
  def splitter(string, options) when is_binary(string) do
    locale = Keyword.get(options, :locale, @default_locale)
    break = Keyword.get(options, :break, :word)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- validate(:locale, locale) do
      Stream.unfold(string, &Break.next(&1, locale, break, options))
    end
  end

  @doc """
  Returns next segment in a string.

  ## Arguments

  * `string` is any `String.t`.

  * `options` is a keyword list of
    options.

  ## Returns

  A tuple with the segment and the remainder of the string or `""`
  in case the String reached its end.

  * `{next_string, rest_of_the_string}`

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_locales/0`.
    The default is "root" which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `:word`.

  * `:suppressions` is a boolean which,
    if `true`, will suppress breaks for common
    abbreviations defined for the `locale`. The
    default is `true`.

  ## Examples

      iex> Unicode.String.next "This is a sentence. And another.", break: :word
      {"This", " is a sentence. And another."}

      iex> Unicode.String.next "This is a sentence. And another.", break: :sentence
      {"This is a sentence. ", "And another."}

  """
  def next(string, options) when is_binary(string) do
    locale = Keyword.get(options, :locale, @default_locale)
    break = Keyword.get(options, :break, :word)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- validate(:locale, locale) do
      Break.next(string, locale, break, options)
    end
  end

  @doc """
  Splits a string according to the
  specified break type.

  ## Arguments

  * `string` is any `String.t`.

  * `options` is a keyword list of
    options.

  ## Returns

  A list of strings after applying the
  specified break rules.

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_locales/0`.
    The default is "root" which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `:word`.

  * `:suppressions` is a boolean which,
    if `true`, will suppress breaks for common
    abbreviations defined for the `locale`. The
    default is `true`.

  * `:trim` is a boolean indicating if segments
    the are comprised of only white space are to be
    excluded fromt the returned list.  The default
    is `false`.

  ## Examples

      iex> Unicode.String.split "This is a sentence. And another.", break: :word
      ["This", " ", "is", " ", "a", " ", "sentence", ".", " ", "And", " ", "another",
       "."]

      iex> Unicode.String.split "This is a sentence. And another.", break: :word, trim: true
      ["This", "is", "a", "sentence", ".", "And", "another", "."]

      iex> Unicode.String.split "This is a sentence. And another.", break: :sentence
      ["This is a sentence. ", "And another."]

  """
  def split(string, options) when is_binary(string) do
    locale = Keyword.get(options, :locale, @default_locale)
    break = Keyword.get(options, :break, :word)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- validate(:locale, locale) do
      Break.split(string, locale, break, options)
    end
    |> maybe_trim(options[:trim])
  end

  defp maybe_trim(list, true) do
    Enum.reject(list, &Property.white_space?/1)
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
