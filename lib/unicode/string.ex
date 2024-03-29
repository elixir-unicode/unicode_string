defmodule Unicode.String do
  @moduledoc """
  This module provides functions that implement some
  of the [Unicode](https://unicode.org) standards:

  * The [Unicode Case Mapping](https://www.unicode.org/versions/Unicode13.0.0/ch03.pdf) algorithm
    to provide mapping to upper, lower and title case text.

  * The [Unicode Case Folding](https://www.unicode.org/versions/Unicode13.0.0/ch03.pdf) algorithm
    to provide case-independent equality checking irrespective of language or script.

  * The [Unicode Segmentation](https://unicode.org/reports/tr29/) algorithm to detect,
    break or split strings into grapheme clusters, words and sentences.

  * The [Unicode Line Breaking](https://www.unicode.org/reports/tr14/) algorithm to determine
    line break placement to support word-wrapping.

  """

  alias Unicode.Property
  alias Unicode.String.Break
  alias Unicode.String.Segment
  alias Unicode.String.Case
  alias Unicode.String.Dictionary

  defdelegate fold(string), to: Unicode.String.Case.Folding
  defdelegate fold(string, type), to: Unicode.String.Case.Folding

  defguard is_language(language) when (byte_size(language) == 2 or byte_size(language) == 3)
  defguard is_script(script) when byte_size(script) == 4
  defguard is_territory(territory) when byte_size(territory) == 2

  @type string_interval :: {String.t(), String.t()}
  @type break_type :: :grapheme | :word | :line | :sentence
  @type error_return :: {:error, String.t()}

  @type option :: {:locale, String.t() | map}
          | {:break, break_type}
          | {:suppressions, boolean}


  @type split_option :: {:locale, String.t() | map}
          | {:break, break_type}
          | {:suppressions, boolean}
          | {:trim, boolean}

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

  * No string normalization is performed. Where the
    normalization state of the string cannot be guaranteed
    it is recommended they be normalized before comparison
    using `String.normalize(string, :nfc)`.

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

  * `string_interval` is any 2-tuple consisting
    of the string before a possible break and the string
    after a possible break.

  * `options` is a keyword list of
    options.

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_segmentation_locales/0` or
    `Unicode.String.Dictionary.known_dictionary_locales/0`.
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

  ## Returns

  * `true` or `false` or

  * raises an exception if there is an error.

  ## Examples

      iex> Unicode.String.break? {"This is ", "some words"}
      true

      iex> Unicode.String.break? {"This is ", "some words"}, break: :sentence
      false

      iex> Unicode.String.break? {"This is one. ", "This is some words."}, break: :sentence
      true

  """
  @spec break?(string_interval :: string_interval(), options :: list(option())) ::
    boolean | no_return()

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

  * `string_interval` is any 2-tuple consisting
    of the string before a possible break and the string
    after a possible break.

  * `options` is a keyword list of
    options.

  ## Options

  * `:locale` is any locale returned by
    `Unicode.String.Segment.known_segmentation_locales/0` or
    `Unicode.String.Dictionary.known_dictionary_locales/0`.
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

  ## Returns

  A tuple indicating if a break would
  be applicable at this point between
  `string_before` and `string_after`.

  * `{:break, {string_before, {matched_string, remaining_string}}}` or

  * `{:no_break, {string_before, {matched_string, remaining_string}}}` or

  * `{:error, reason}`.

  ## Examples

      iex> Unicode.String.break {"This is ", "some words"}
      {:break, {"This is ", {"s", "ome words"}}}

      iex> Unicode.String.break {"This is ", "some words"}, break: :sentence
      {:no_break, {"This is ", {"s", "ome words"}}}

      iex> Unicode.String.break {"This is one. ", "This is some words."}, break: :sentence
      {:break, {"This is one. ", {"T", "his is some words."}}}

  """
 @spec break(string_interval :: string_interval(), options :: list(option())) ::
    break_match | error_return

  def break({string_before, string_after}, options \\ []) do
    break = Keyword.get(options, :break, @default_break)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- segmentation_locale_from_options(break, options),
         {:ok, _dictionary} <- Dictionary.ensure_dictionary_loaded_if_available(locale) do
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
    `Unicode.String.Segment.known_segmentation_locales/0` or
    `Unicode.String.Dictionary.known_dictionary_locales/0`.
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
  @spec splitter(string :: String.t(), split_options :: list(split_option)) ::
    function | error_return

  def splitter(string, options) when is_binary(string) do
    break = Keyword.get(options, :break, @default_break)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- segmentation_locale_from_options(break, options),
         {:ok, _dictionary} <- Dictionary.ensure_dictionary_loaded_if_available(locale) do
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
    `Unicode.String.Segment.known_segmentation_locales/0` or
    `Unicode.String.Dictionary.known_dictionary_locales/0` or
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
  @spec next(string :: String.t(), split_options :: list(split_option)) ::
    String.t() | nil | error_return

  def next(string, options \\ []) when is_binary(string) do
    break = Keyword.get(options, :break, @default_break)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- segmentation_locale_from_options(break, options) do
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
    `Unicode.String.Segment.known_segmentation_locales/0`  or
    `Unicode.String.Dictionary.known_dictionary_locales/0` or
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
  @spec split(string :: String.t(), split_options :: list(split_option)) ::
    [String.t(), ...] | error_return

  def split(string, options \\ []) when is_binary(string) do
    break = Keyword.get(options, :break, @default_break)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- segmentation_locale_from_options(break, options) do
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
    `Unicode.String.Segment.known_segmentation_locales/0` or
    `Unicode.String.Dictionary.known_dictionary_locales/0` or
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

  @spec stream(string :: String.t(), split_options :: list(split_option)) ::
    Enumerable.t() | {:error, String.t()}

  def stream(string, options \\ []) do
    break = Keyword.get(options, :break, @default_break)

    with {:ok, break} <- validate(:break, break),
         {:ok, locale} <- segmentation_locale_from_options(break, options) do
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

  ### Arguments

  * `string` is any `t:String.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is any [ISO 639](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)
    language code or a [LanguageTag](https://hexdocs.pm/ex_cldr/Cldr.LanguageTag.html)
    which provides integration with [ex_cldr](https://hex.pm/packages/ex_cldr)
    applications.  The default is `:any` which signifies the
    application of the base Unicode casing algorithm.

  ### Notes

  * The locale option determines the use of certain locale-specific
    casing rules.  Where no specific casing rules apply to
    the given locale, the base Unicode casing algorithm is
    applied. The locales which have customized casing rules
    are returned by `Unicode.String.special_casing_locales/0`.

  ### Returns

  * `downcased_string`

  ### Examples

      # Basic case transformation
      iex> Unicode.String.upcase("the quick brown fox")
      "THE QUICK BROWN FOX"

      # Dotted-I in Turkish and Azeri
      iex> Unicode.String.upcase("Diyarbakır", locale: :tr)
      "DİYARBAKIR"

      # Upper case in Greek removes diacritics
      iex> Unicode.String.upcase("Πατάτα, Αέρας, Μυστήριο", locale: :el)
      "ΠΑΤΑΤΑ, ΑΕΡΑΣ, ΜΥΣΤΗΡΙΟ"

  """
  @doc since: "1.3.0"

  @spec upcase(String.t(), Keyword.t()) :: String.t()
  def upcase(string, options \\ []) when is_list(options) do
    with {:ok, locale} <- casing_locale_from_options(options) do
      Case.Mapping.upcase(string, locale)
    end
  end

  @doc """
  Converts all characters in the given string to lower case
  according to the Unicode Casing algorithm.

  ### Arguments

  * `string` is any `t:String.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is any [ISO 639](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)
    language code or a [LanguageTag](https://hexdocs.pm/ex_cldr/Cldr.LanguageTag.html)
    which provides integration with [ex_cldr](https://hex.pm/packages/ex_cldr)
    applications.  The default is `:any` which signifies the
    application of the base Unicode casing algorithm.

  ### Notes

  * The locale option determines the use of certain locale-specific
    casing rules.  Where no specific casing rules apply to
    the given locale, the base Unicode casing algorithm is
    applied. The locales which have customized casing rules
    are returned by `Unicode.String.special_casing_locales/0`.

  ### Returns

  * `downcased_string`

  ### Examples

      iex> Unicode.String.downcase("THE QUICK BROWN FOX")
      "the quick brown fox"

      # Lower case Greek with a final sigma
      iex> Unicode.String.downcase("ὈΔΥΣΣΕΎΣ", locale: :el)
      "ὀδυσσεύς"

      # Lower case in Turkish and Azeri correctly handles
      # undotted-i and undotted-I
      iex> Unicode.String.downcase("DİYARBAKIR", locale: :tr)
      "diyarbakır"

  """
  @doc since: "1.3.0"

  @spec downcase(String.t(), Keyword.t()) :: String.t()
  def downcase(string, options \\ []) when is_list(options) do
    with {:ok, locale} <- casing_locale_from_options(options) do
      Case.Mapping.downcase(string, locale)
    end
  end

  @doc """
  Converts the given string to title case
  according to the Unicode Casing algorithm.

  Title casing is the process of transforming
  the first character of each word in a string
  to upper case and the following characters
  in the word to lower case.

  As a result this algorithm does not conform
  to the norms of all languages and cultures.
  However special processing is performed for
  the Dutch dipthong "IJ" when using the `:nl`
  casing locale.

  Further work will focus on improving title
  casing of Greek dipthongs.

  ### Arguments

  * `string` is any `t:String.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is any [ISO 639](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)
    language code or a [LanguageTag](https://hexdocs.pm/ex_cldr/Cldr.LanguageTag.html)
    which provides integration with [ex_cldr](https://hex.pm/packages/ex_cldr)
    applications.  The default is `:any` which signifies the
    application of the base Unicode casing algorithm.

  ### Notes

  * The locale option determines the use of certain locale-specific
    casing rules.  Where no specific casing rules apply to
    the given locale, the base Unicode casing algorithm is
    applied. The locales which have customized casing rules
    are returned by `Unicode.String.special_casing_locales/0`.

  * The string is broken into words using
    `Unicode.String.break/2` which implements the
    [Unicode segmentation algorithm](https://unicode.org/reports/tr29/).

  ### Returns

  * `title_cased_string`.

  ### Examples

      iex> Unicode.String.titlecase("THE QUICK BROWN FOX")
      "The Quick Brown Fox"

      # Title case Dutch with leading dipthong
      iex> Unicode.String.titlecase("ijsselmeer", locale: :nl)
      "IJsselmeer"

  """
  @doc since: "1.3.0"

  @spec titlecase(String.t(), Keyword.t()) :: String.t()
  def titlecase(string, options \\ []) when is_list(options) do
    with {:ok, casing_locale} <- casing_locale_from_options(options),
         {:ok, segmentation_locale} <- segmentation_locale_from_options(:word, options) do
      stream_options = Keyword.merge(options, break: :word, locale: segmentation_locale)

      string
      |> stream(stream_options)
      |> Enum.map(&Case.Mapping.titlecase(&1, casing_locale))
      |> Enum.join()
    end
  end

  # These locales have some aadditional processing
  # beyond that specified in SpecialCasing.txt
  @special_casing_locales [:nl, :el]
  @casing_locales (@special_casing_locales ++ Unicode.Utils.known_casing_locales())
                  |> Enum.sort()

  @doc """
  Returms a list of locales that have special
  casing rules.

  ### Example

      iex> Unicode.String.special_casing_locales()
      [:az, :el, :lt, :nl, :tr]

  """
  def special_casing_locales do
    @casing_locales
  end

  #
  # Helpers
  #

  @doc false
  def casing_locale(locale) do
    casing_locale_from_options(locale: locale)
  end

  @doc false
  def segmentation_locale(break, locale) do
    segmentation_locale_from_options(break, locale: locale)
  end

  defp casing_locale_from_options(options) do
    options
    |> Keyword.get(:locale)
    |> match_locale(@casing_locales, :any)
    |> wrap(:ok)
  end

  @segmentation_locales Segment.known_segmentation_locales()
  @dictionary_locales Dictionary.known_dictionary_locales()

  defp segmentation_locale_from_options(:word, options) do
    locale =  Keyword.get(options, :locale)
    segmentation_locale =  match_locale(locale, @segmentation_locales, :root)
    dictionary_locale = match_locale(locale, @dictionary_locales, nil)

    if dictionary_locale do
      Dictionary.ensure_dictionary_loaded_if_available(dictionary_locale)
    end

    (dictionary_locale || segmentation_locale)
    |> wrap(:ok)
  end

  defp segmentation_locale_from_options(_break, options) do
    options
    |> Keyword.get(:locale)
    |> match_locale(@segmentation_locales, :root)
    |> wrap(:ok)
  end

  @doc false
  def dictionary_locale(locale) do
    dictionary_locale_from_options(locale: locale)
  end

  @dictionary_locales Dictionary.known_dictionary_locales()

  defp dictionary_locale_from_options(options) do
    options
    |> Keyword.get(:locale)
    |> match_locale(@dictionary_locales, nil)
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
    |> Enum.map(&atomize/1)
    |> find_matching_locale(known_locales, default)
  end

  defp match_locale(locale, known_locales, default) when is_binary(locale) do
    locale
    |> String.split(["-", "_"])
    |> build_candidate_locales()
    |> find_matching_locale(known_locales, default)
  end

  defp match_locale(locale, known_locales, default) when is_atom(locale) do
    if locale in known_locales do
      locale
    else
      match_locale(to_string(locale), known_locales, default)
    end
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
    Enum.reduce_while(candidates, default, fn candidate, default ->
      if candidate in known_locales do
        {:halt, candidate}
      else
        {:cont, default}
      end
    end)
  end

  defp build_candidate_locales([language]) when is_language(language) do
    language
    |> String.downcase()
    |> atomize()
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
  end

  defp build_candidate_locales([language, territory | _rest])
       when is_language(language) and is_territory(territory) do
    language = downcase(language)
    territory = upcase(territory)

    Enum.reject([atomize("#{language}-#{territory}"), atomize(language)], &is_nil/1)
  end

  defp build_candidate_locales([language, script, territory | _rest])
       when is_language(language) and is_script(script) and is_territory(territory) do
    language = downcase(language)
    script = titlecase(script)
    territory = upcase(territory)

    Enum.reject([
      atomize("#{language}-#{territory}"),
      atomize("#{language}-#{script}"),
      atomize(language)
    ], &is_nil/1)
  end

  defp build_candidate_locales([language, script | _rest])
      when is_language(language) and is_script(script) do
    language = downcase(language)
    script = titlecase(script)

    Enum.reject([atomize("#{language}-#{script}"), atomize(language)], &is_nil/1)
  end

  defp build_candidate_locales([language | _rest])  when is_language(language) do
    build_candidate_locales([language])
  end

  defp build_candidate_locales(["root"]) do
    [:root]
  end

  defp build_candidate_locales(_other) do
    []
  end

  defp atomize(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError ->
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
