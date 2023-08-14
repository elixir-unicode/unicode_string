defmodule Unicode.String do
  @moduledoc """
  This module provides functions that implement some
  of the [Unicode](https://unicode.org) standards:

  * The [Unicode Case Folding](https://www.unicode.org/versions/Unicode13.0.0/ch03.pdf) algorithm
    to provide case-independent equality checking irrespective of language or script.

  * The [Unicode Segmentation](https://unicode.org/reports/tr29/) algorithm to detect,
    break or splut strings into grapheme clusters, works and sentences.

  * The [Unicode Line Breaking](https://www.unicode.org/reports/tr14/) algorithm to determine
    line breaks (as in word-wrapping).

  """

  alias Unicode.Property
  alias Unicode.String.Break
  alias Unicode.String.Segment
  alias Unicode.String.Case

  defdelegate fold(string), to: Unicode.String.Case.Folding
  defdelegate fold(string, type), to: Unicode.String.Case.Folding

  @type string_interval :: {String.t(), String.t()}
  @type break_type :: :grapheme | :word | :line | :sentence
  @type error_return :: {:error, String.t()}

  @type options :: [
          {:locale, String.t() | map}
          | {:break, break_type}
          | {:suppressions, boolean}
        ]

  @type split_options :: [
          {:locale, String.t() | map}
          | {:break, break_type}
          | {:suppressions, boolean}
          | {:trim, boolean}
        ]

  @type break_or_no_break :: :break | :no_break

  @type break_match ::
          {break_or_no_break, {String.t(), {String.t(), String.t()}}}
          | {break_or_no_break, {String.t(), String.t()}}

  @type mode_or_language :: :turkic | nil | %{language: atom()}

  @default_locale "root"
  @default_break :word

  @doc """
  Compares two strings in a case insensitive
  manner.

  Case folding is applied to the two string
  arguments which are then compared with the
  `==` operator.

  ## Arguments

  * `string_a` and `string_b` are two strings
    to be compared

  ## Returns

  * `true` or `false`

  ## Notes

  * This function applies the [Unicode Case Folding
    algorithm](https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf)

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
  @spec equals_ignoring_case?(String.t(), String.t(), mode_or_language()) :: boolean
  def equals_ignoring_case?(string_a, string_b, mode_or_language_tag \\ nil) do
    fold(string_a, mode_or_language_tag) == fold(string_b, mode_or_language_tag)
  end

  @doc """
  Returns a boolean indicating if the
  requested break is applicable
  at the point between the two string
  segments represented by `{string_before, string_after}`.

  ## Arguments

  * `string` is any `t:String.t/0`.

  * `options` is a keyword list of
    options.

  ## Returns

  * `true` or `false` or

  * raises an exception if there is an error

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_locales/0`.
    The default is #{inspect(@default_locale)} which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `#{inspect(@default_break)}`.

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

  * `string` is any `t:String.t/0`.

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
    The default is #{inspect(@default_locale)} which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `#{inspect(@default_break)}`.

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
    break = Keyword.get(options, :break, @default_break)

    with {:ok, locale} <- segmentation_locale_from_options(options),
         {:ok, break} <- validate(:break, break) do
      Break.break({string_before, string_after}, locale, break, options)
    end
  end

  @doc """
  Returns an enumerable that splits a string on demand.

  ## Arguments

  * `string` is any `t:String.t/0`.

  * `options` is a keyword list of
    options.

  ## Returns

  * A function that implements the enumerable
    protocol or

  * `{:error, reason}`

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_locales/0`.
    The default is #{inspect(@default_locale)} which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `#{inspect(@default_break)}`.

  * `:suppressions` is a boolean which,
    if `true`, will suppress breaks for common
    abbreviations defined for the `locale`. The
    default is `true`.

  * `:trim` is a boolean indicating if segments
    the are comprised of only white space are to be
    excluded from the returned list.  The default
    is `false`.

  ## Examples

      iex> enum = Unicode.String.splitter "This is a sentence. And another.", break: :word, trim: true
      iex> Enum.take enum, 3
      ["This", "is", "a"]

  """
  @spec splitter(String.t(), split_options) :: function | error_return
  def splitter(string, options) when is_binary(string) do
    break = Keyword.get(options, :break, @default_break)

    with {:ok, locale} <- segmentation_locale_from_options(options),
         {:ok, break} <- validate(:break, break) do
      Stream.unfold(string, &Break.next(&1, locale, break, options))
    end
  end

  @doc """
  Returns next segment in a string.

  ## Arguments

  * `string` is any `t:String.t/0`.

  * `options` is a keyword list of
    options.

  ## Returns

  A tuple with the segment and the remainder of the string or `""`
  in case the String reached its end.

  * `{next_string, rest_of_the_string}` or

  * `{:error, reason}`

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_locales/0` or
    a [Cldr.LanguageTag](https://hexdocs.pm/ex_cldr/Cldr.LanguageTag.html)
    struct. The default is #{inspect(@default_locale)} which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `#{inspect(@default_break)}`.

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
  @spec next(String.t(), split_options) :: String.t() | nil | error_return
  def next(string, options \\ []) when is_binary(string) do
    break = Keyword.get(options, :break, @default_break)

    with {:ok, locale} <- segmentation_locale_from_options(options),
         {:ok, break} <- validate(:break, break) do
      Break.next(string, locale, break, options)
    end
  end

  @doc """
  Splits a string according to the
  specified break type.

  ## Arguments

  * `string` is any `t:String.t/0`.

  * `options` is a keyword list of
    options.

  ## Returns

  * A list of strings after applying the
    specified break rules or

  * `{:error, reason}`

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_locales/0` or
    a [Cldr.LanguageTag](https://hexdocs.pm/ex_cldr/Cldr.LanguageTag.html)
    struct. The default is #{inspect(@default_locale)} which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `#{inspect(@default_break)}`.

  * `:suppressions` is a boolean which,
    if `true`, will suppress breaks for common
    abbreviations defined for the `locale`. The
    default is `true`.

  * `:trim` is a boolean indicating if segments
    the are comprised of only white space are to be
    excluded from the returned list.  The default
    is `false`.

  ## Examples

      iex> Unicode.String.split "This is a sentence. And another.", break: :word
      ["This", " ", "is", " ", "a", " ", "sentence", ".", " ", "And", " ", "another", "."]

      iex> Unicode.String.split "This is a sentence. And another.", break: :word, trim: true
      ["This", "is", "a", "sentence", ".", "And", "another", "."]

      iex> Unicode.String.split "This is a sentence. And another.", break: :sentence
      ["This is a sentence. ", "And another."]

  """
  @spec split(String.t(), split_options) :: [String.t(), ...] | error_return
  def split(string, options \\ []) when is_binary(string) do
    break = Keyword.get(options, :break, @default_break)

    with {:ok, locale} <- segmentation_locale_from_options(options),
         {:ok, break} <- validate(:break, break) do
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

  @doc """
  Return a stream that breaks a string into
  graphemes, words, sentences or line breaks.

  ## Arguments

  * `string` is any `t:String.t/0`.

  * `options` is a keyword list of
    options.

  ## Returns

  * A stream that is an `t:Enumerable.t/0` that
    can be used with the functions in the `Stream`
    or `Enum` modules.

  * `{:error, reason}`

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_locales/0` or
    a [Cldr.LanguageTag](https://hexdocs.pm/ex_cldr/Cldr.LanguageTag.html)
    struct. The default is #{inspect(@default_locale)} which corresponds
    to the break rules defined by the
    [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  * `:break` is the type of break. It is one of
    `:grapheme`, `:word`, `:line` or `:sentence`. The
    default is `#{inspect(@default_break)}`.

  * `:suppressions` is a boolean which,
    if `true`, will suppress breaks for common
    abbreviations defined for the `locale`. The
    default is `true`.

  * `:trim` is a boolean indicating if segments
    the are comprised of only white space are to be
    excluded from the returned list.  The default
    is `false`.

  ## Examples

    iex> Enum.to_list Unicode.String.stream("this is a set of words", trim: true)
    ["this", "is", "a", "set", "of", "words"]

    iex> Enum.to_list Unicode.String.stream("this is a set of words", break: :sentence, trim: true)
    ["this is a set of words"]

  """
  @doc since: "1.2.0"

  @spec stream(String.t(), Keyword.t()) :: Enumerable.t() | {:error, String.t()}
  def stream(string, options \\ []) do
    break = Keyword.get(options, :break, @default_break)

    with {:ok, locale} <- segmentation_locale_from_options(options),
         {:ok, break} <- validate(:break, break) do
      Stream.resource(
        fn -> string end,
        fn string ->
          case Break.next(string, locale, break, options) do
            nil -> {:halt, ""}
            {break, rest} -> {[break], rest}
          end
        end,
        fn _ -> :ok end
      )
    end
  end

  @doc """
  Converts all characters in the given string to upper case
  according to the Unicode Casing algorithm.

  """
  def upcase(string, options \\ []) do
    with {:ok, locale} <- casing_locale_from_options(options) do
      Case.Mapping.upcase(string, locale)
    end
  end

  @doc """
  Converts all characters in the given string to lower case
  according to the Unicode Casing algorithm.

  """
  def downcase(string, options \\ []) do
    with {:ok, locale} <- casing_locale_from_options(options) do
      Case.Mapping.downcase(string, locale)
    end
  end

  @doc """
  Converts all words in the given string to title case
  according to the Unicode Casing algorithm.

  The string is broken into words (according to the
  Unicode break algorithm) and each word then has its
  first character capitalized and all other letters
  downcased.

  """

  def titlecase(string, options \\ []) do
    with {:ok, casing_locale} <- casing_locale_from_options(options),
         {:ok, segmentation_locale} <- segmentation_locale_from_options(options) do

      stream_options = Keyword.merge(options, break: :word, locale: segmentation_locale)

      string
      |> stream(stream_options)
      |> Enum.map(&Case.Mapping.titlecase(&1, casing_locale))
      |> Enum.join()
    end
  end

  #
  # Helpers
  #

  @doc false
  def casing_locale(locale) do
    casing_locale_from_options(locale: locale)
  end

  @doc false
  def segmentation_locale(locale) do
    segmentation_locale_from_options(locale: locale)
  end

  defp casing_locale_from_options(options) do
    options
    |> Keyword.get(:locale)
    |> match_locale([:nl | Unicode.Utils.known_casing_locales()], :any)
    |> wrap(:ok)
  end

  defp segmentation_locale_from_options(options) do
    options
    |> Keyword.get(:locale)
    |> match_locale(Segment.known_segmentation_locales(), :root)
    |> wrap(:ok)
  end

  defp wrap({:error, _} = error, _) do
    error
  end

  defp wrap(term, atom) do
    {atom, term}
  end

  defp match_locale(nil, _known_locales, default) do
    default
  end

  # The Enum.sort/1 here relies on the coincidental fact tha the three fields
  # are alphabetically in the order we already want

  defp match_locale(locale, known_locales, default) when is_struct(locale, Cldr.LanguageTag) do
    locale
    |> Map.take([:canonical_locale_name, :cldr_locale_name, :language])
    |> Enum.sort()
    |> Keyword.values()
    |> Enum.uniq()
    |> find_matching_locale(known_locales, default)
  end

  defp match_locale(locale, known_locales, default) when is_binary(locale) do
    locale
    |> String.split(["-", "_"])
    |> build_candidate_locales()
    |> find_matching_locale(known_locales, default)
  end

  defp match_locale(locale, known_locales, default) when is_atom(locale) do
    if locale in known_locales, do: locale, else: default
  end

  # Means it was a segment match request
  defp match_locale(locale, _known_locales, :root) do
    {:error, Segment.unknown_locale_error(locale)}
  end

  # Means it was a casing match request
  defp match_locale(locale, _known_locales, :any) do
    {:error, Case.Mapping.unknown_locale_error(locale)}
  end

  def find_matching_locale(candidates, known_locales, default) do
    candidates
    |> Enum.reduce_while(default, fn candidate, current ->
      case match_locale(candidate, known_locales, nil) do
        nil -> {:cont, current}
        found -> {:halt, found}
      end
    end)
  end

  defp build_candidate_locales([language]) when byte_size(language) == 2 do
    language
    |> String.downcase()
    |> atomize()
    |> List.wrap
    |> Enum.reject(&is_nil/1)
  end

  defp build_candidate_locales([language, territory | _rest])
      when byte_size(language) == 2 and byte_size(territory) == 2 do
    language = String.downcase(language)
    territory = String.upcase(territory)

    Enum.reject([atomize("#{language}-#{territory}"), atomize(language)], &is_nil/1)
  end

  defp build_candidate_locales(["root"]) do
    [:root]
  end

  defp build_candidate_locales(_other) do
    []
  end

  defp atomize(string) do
    String.to_existing_atom(string)
  rescue ArgumentError ->
    nil
  end

  @breaks [:word, :grapheme, :line, :sentence]

  defp validate(:break, break) do
    if break in @breaks do
      {:ok, break}
    else
      {:error, "Unknown break #{inspect(break)}. Valid breaks are #{inspect(@breaks)}"}
    end
  end

end
