defmodule Unicode.String do
  @moduledoc """
  This module provides functions that implement somee
  of the [Unicode](https://unicode.org) stanards:

  * The [Unicode Case Folding](https://www.unicode.org/versions/Unicode13.0.0/ch03.pdf) algorithm
    to provide case-independent equality checking irrespective of language or script.

  * The [Unicode Segmentation](https://unicode.org/reports/tr29/) algorithm to detect,
    break or splut strings into grapheme clusters, works and sentences.

  """

  alias Unicode.String.Segment
  alias Unicode.String.Break
  alias Unicode.Property

  defdelegate fold(string), to: Unicode.String.Case.Folding
  defdelegate fold(string, type), to: Unicode.String.Case.Folding

  @type string_interval :: {String.t, String.t}
  @type break_type :: :grapheme | :word | :line | :sentence
  @type error_return :: {:error, String.t}

  @type options :: [
    {:locale, String.t},
    {:break, break_type},
    {:suppressions, boolean}
  ]

  @type split_options :: [
    {:locale, String.t},
    {:break, break_type},
    {:suppressions, boolean},
    {:trim, boolean}
  ]

  @type break_or_no_break :: :break | :no_break

  @type break_match ::
    {break_or_no_break, {String.t, {String.t, String.t}}} |
    {break_or_no_break, {String.t, String.t}}

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
  @spec equals_ignoring_case?(String.t, String.t, atom()) :: boolean
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

  * `true` or `false` or

  * raises an exception if there is an error

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
  @spec break?(string_interval, options) :: boolean
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

  * `{:break, {string_before, {matched_string, remaining_string}}}` or

  * `{:no_break, {string_before, {matched_string, remaining_string}}}` or

  * `{:error, reason}`

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
      {:break, {"This is ", {"s", "ome words"}}}

      iex> Unicode.String.break {"This is ", "some words"}, break: :sentence
      {:no_break, {"This is ", {"s", "ome words"}}}

      iex> Unicode.String.break {"This is one. ", "This is some words."}, break: :sentence
      {:break, {"This is one. ", {"T", "his is some words."}}}

  """
  @spec break(string_interval, options) :: break_match | error_return
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

  * A function that implements the enumerable
    protocol or

  * `{:error, reason}`

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
  @spec splitter(String.t, split_options) :: function | error_return
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

  * `{next_string, rest_of_the_string}` or

  * `{:error, reason}`

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
  @spec next(String.t, split_options) :: String.t | nil | error_return
  def next(string, options \\ []) when is_binary(string) do
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

  * A list of strings after applying the
    specified break rules or

  * `{:error, reason}`

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
      ["This", " ", "is", " ", "a", " ", "sentence", ".", " ", "And", " ", "another", "."]

      iex> Unicode.String.split "This is a sentence. And another.", break: :word, trim: true
      ["This", "is", "a", "sentence", ".", "And", "another", "."]

      iex> Unicode.String.split "This is a sentence. And another.", break: :sentence
      ["This is a sentence. ", "And another."]

  """
  @spec split(String.t, split_options) :: [String.t, ...] | error_return
  def split(string, options \\ []) when is_binary(string) do
    locale = Keyword.get(options, :locale, @default_locale)
    break = Keyword.get(options, :break, :word)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- validate(:locale, locale) do
      Break.split(string, locale, break, options)
    end
    |> maybe_trim(options[:trim])
  end

  defp maybe_trim(list, true) when is_list(list) do
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
