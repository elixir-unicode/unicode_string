defmodule Unicode.String.Case.Mapping do
  @moduledoc """
  The [Unicode Case Mapping](https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf) algorithm
  defines the process and data to transform text into upper case, lower case or title case.

  Since most languages are not bicameral, characters which have no appropriate mapping remain unchanged.

  Three case mapping functions are provided as a public API which have their implementations in this module:

  * `Unicode.String.upcase/2` which will convert text to upper case characters.
  * `Unicode.String.downcase/2` which will convert text to lower case characters.
  * `Unicode.String.titlecase/2` which will convert text to title case.  Title case means
    that the first character or each word is set to upper case and all other characters in
    the word are set to lower case. `Unicode.String.split/2` is used to split the string
    into words before title casing.

  Each function operates in a locale-aware manner implementing some basic capabilities:

  * Casing rules for the Turkish dotted capital `I` and dotless small `i`.
  * Casing rules for the retention of dots over `i` for Lithuanian letters with additional accents.
  * Titlecasing of IJ at the start of words in Dutch.
  * Removal of accents when upper casing letters in Greek.

  There are other casing rules that are not currently implemented such as:

  * Titlecasing of second or subsequent letters in words in orthographies that include
    caseless letters such as apostrophes.
  * Uppercasing of U+00DF `ß` latin small letter sharp `s` to U+1E9E `ẞ` latin capital letter
    sharp `s`.

  ### Examples

      # Basic case transformation
      iex> Unicode.String.Case.Mapping.upcase("the quick brown fox")
      "THE QUICK BROWN FOX"

      # Dotted-I in Turkish and Azeri
      iex> Unicode.String.Case.Mapping.upcase("Diyarbakır", :tr)
      "DİYARBAKIR"

      # Upper case in Greek removes diacritics
      iex> Unicode.String.Case.Mapping.upcase("Πατάτα, Αέρας, Μυστήριο", :el)
      "ΠΑΤΑΤΑ, ΑΕΡΑΣ, ΜΥΣΤΗΡΙΟ"

      # Lower case Greek with a final sigma
      iex> Unicode.String.Case.Mapping.downcase("ὈΔΥΣΣΕΎΣ", :el)
      "ὀδυσσεύς"

      # Title case Dutch with leading dipthong
      iex> Unicode.String.Case.Mapping.titlecase("ijsselmeer", :nl)
      "IJsselmeer"

  """

  alias Unicode.Utils

  @sigma 0x03A3
  @lower_sigma <<0x03C3::utf8>>
  @sigma_byte_size byte_size(<<@sigma::utf8>>)

  # See table Table 3-17 of https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf
  # for details of the contexts

  # These regexes can probably be converted to another form
  # which may further enable binary optimmization.
  @final_sigma_before Unicode.Regex.expand_regex("\\p{cased}(\\p{Case_Ignorable})*")
  @final_sigma_after Unicode.Regex.expand_regex("(\\p{Case_Ignorable})*\\p{cased}")

  @after_soft_dotted Unicode.Regex.expand_regex("[\\p{Soft_Dotted}]([^\\p{ccc=230}\\p{ccc=0}])*")
  @more_above Unicode.Regex.expand_regex("[^\\p{ccc=230}\\p{ccc=0}]*[\\p{ccc=230}]")
  @before_dot Unicode.Regex.expand_regex("([^\\p{ccc=230}\\p{ccc=0}])*[\u0307]")
  @after_i Unicode.Regex.expand_regex("[I]([^\\p{ccc=230}\\p{ccc=0}])*")

  utf8_bytes_for_codepoint = fn codepoint ->
    byte_size(<<codepoint::utf8>>)
  end

  define_casing_function = fn
    casing, codepoint, replace, language, nil ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)
      replacement = :unicode.characters_to_binary(replace)

      defp casing(
             string,
             <<unquote(codepoint)::utf8, rest::binary>>,
             unquote(casing),
             unquote(language),
             bytes_so_far,
             acc
           ) do
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
          unquote(replacement) | acc
        ])
      end

    casing, codepoint, replace, language, "final_sigma" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)
      replacement = :unicode.characters_to_binary(replace)

      defp casing(
             string,
             <<@sigma::utf8, rest::binary>>,
             unquote(casing),
             unquote(language),
             bytes_so_far,
             acc
           ) do
        <<prior::binary-size(bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(~r/#{@final_sigma_before}/u, prior) && !Regex.match?(~r/#{@final_sigma_after}/u, rest) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
            unquote(replacement) | acc
          ])
        else
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
            @lower_sigma | acc
          ])
        end
      end

    casing, codepoint, replace, language, "not_before_dot" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)
      replacement = :unicode.characters_to_binary(replace)

      defp casing(
             string,
             <<unquote(codepoint)::utf8, rest::binary>>,
             unquote(casing),
             unquote(language),
             bytes_so_far,
             acc
           ) do
        <<prior::binary-size(bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if !Regex.match?(~r/#{@before_dot}/u, prior) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
            unquote(replacement) | acc
          ])
        else
          this =
            casing(
              <<unquote(codepoint)::utf8>>,
              <<unquote(codepoint)::utf8>>,
              unquote(casing),
              :any,
              0,
              acc
            )

          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [this | acc])
        end
      end

    casing, codepoint, replace, language, "more_above" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)
      replacement = :unicode.characters_to_binary(replace)

      defp casing(
             string,
             <<unquote(codepoint)::utf8, rest::binary>>,
             unquote(casing),
             unquote(language),
             bytes_so_far,
             acc
           ) do
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(~r/#{@more_above}/u, rest) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
            unquote(replacement) | acc
          ])
        else
          this =
            casing(
              <<unquote(codepoint)::utf8>>,
              <<unquote(codepoint)::utf8>>,
              unquote(casing),
              :any,
              0,
              acc
            )

          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [this | acc])
        end
      end

    casing, codepoint, replace, language, "after_soft_dotted" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)
      replacement = :unicode.characters_to_binary(replace)

      defp casing(
             string,
             <<unquote(codepoint)::utf8, rest::binary>>,
             unquote(casing),
             unquote(language),
             bytes_so_far,
             acc
           ) do
        <<prior::binary-size(bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(~r/#{@after_soft_dotted}/u, prior) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
            unquote(replacement) | acc
          ])
        else
          this =
            casing(
              <<unquote(codepoint)::utf8>>,
              <<unquote(codepoint)::utf8>>,
              unquote(casing),
              :any,
              0,
              acc
            )

          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [this | acc])
        end
      end

    casing, codepoint, replace, language, "after_i" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)
      replacement = :unicode.characters_to_binary(replace)

      defp casing(
             string,
             <<unquote(codepoint)::utf8, rest::binary>>,
             unquote(casing),
             unquote(language),
             bytes_so_far,
             acc
           ) do
        <<prior::binary-size(bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(~r/#{@after_i}/u, prior) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
            unquote(replacement) | acc
          ])
        else
          this =
            casing(
              <<unquote(codepoint)::utf8>>,
              <<unquote(codepoint)::utf8>>,
              unquote(casing),
              :any,
              0,
              acc
            )

          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [this | acc])
        end
      end
  end

  @doc """
  Replace lower case characters with their
  uppercase equivalents.

  Lower case characters are replaced with their
  upper case equivalents. All other characters
  remain unchanged.

  For the Greek language (`:el`), all accents are
  removed prior to capitalization as is the normal
  practise for this language.

  """
  def upcase(string, language \\ :any)

  def upcase(string, :el) do
    Unicode.String.Case.Mapping.Greek.upcase(string)
  end

  def upcase(string, language) when is_atom(language) do
    casing(string, string, :upcase, language, 0, [])
  end

  @doc """
  Replace upper case characters with their
  lower case equivalents.

  """
  def downcase(string, language \\ :any)

  def downcase(string, language) when is_atom(language) do
    casing(string, string, :downcase, language, 0, [])
  end

  @doc """
  Apply to Unicode title case algorithm.

  """
  def titlecase(string, language \\ :any)

  def titlecase(<<i::size(8), j::size(8), rest::binary>>, :nl)
      when i in [?i, ?I] and j in [?j, ?J] do
    "IJ" <> casing(rest, rest, :downcase, :any, 0, [])
  end

  def titlecase(<<first::utf8, rest::binary>>, language) when is_atom(language) do
    casing(<<first::utf8>>, <<first::utf8>>, :titlecase, language, 0, []) <>
      downcase(rest, language)
  end

  # These next four function clauses optimze for ASCII characters.
  # We need to omit the `i` from all ranges since in Turkish and Azeri
  # they upcase to a dotted-capital-I

  defp casing(
         string,
         <<byte::size(8), rest::binary>>,
         :downcase = casing,
         language,
         bytes_so_far,
         acc
       )
       when byte >= ?A and byte <= ?Z and byte != ?I do
    casing(string, rest, casing, language, bytes_so_far + 1, [byte + 32 | acc])
  end

  defp casing(string, <<byte::size(8), rest::binary>>, casing, language, bytes_so_far, acc)
       when casing in [:upcase, :titlecase] and byte >= ?a and byte <= ?z and byte != ?i do
    casing(string, rest, casing, language, bytes_so_far + 1, [byte - 32 | acc])
  end

  defp casing(string, <<byte::size(8), rest::binary>>, casing, language, bytes_so_far, acc)
       when casing in [:upcase, :titlecase] and byte != ?i and byte <= ?~ do
    casing(string, rest, casing, language, bytes_so_far + 1, [byte | acc])
  end

  defp casing(
         string,
         <<byte::size(8), rest::binary>>,
         :downcase = casing,
         language,
         bytes_so_far,
         acc
       )
       when byte != ?I and byte <= ?~ do
    casing(string, rest, casing, language, bytes_so_far + 1, [byte | acc])
  end

  # Generate the mapping functions

  for %{codepoint: codepoint, upper: upper} = casing <- Utils.casing_in_order(),
      upper && upper != codepoint && (codepoint == ?i or codepoint > ?~) do
    %{context: context, language: language} = casing

    define_casing_function.(:upcase, codepoint, upper, language, context)
  end

  for %{codepoint: codepoint, lower: lower} = casing <- Utils.casing_in_order(),
      lower && lower != codepoint && (codepoint == ?I or codepoint > ?~) do
    %{language: language, context: context} = casing

    # Special casing for capital sigma with no context.
    # see the default implementations of casing/5 at the
    # end of this file. Don't generate a function clause for
    # this codepoint here.
    unless codepoint == @sigma and is_nil(context) do
      define_casing_function.(:downcase, codepoint, lower, language, context)
    end
  end

  for %{codepoint: codepoint, title: title} = casing <- Utils.casing_in_order(),
      title && title != codepoint && codepoint > ?~ do
    %{context: context, language: language} = casing

    define_casing_function.(:titlecase, codepoint, title, language, context)
  end

  # End of string, return accumulator
  defp casing(_string, "", _casing, _language, _bytes_so_far, acc) do
    acc
    |> :lists.reverse()
    |> IO.iodata_to_binary()
  end

  # Special case for Greek sigma when no context. This is the only codepoint
  # that has two cases for the language :any. One case with "final_sigma" context
  # and one with no context. This means we can't generate two distinct function
  # clauses for casing/5 so we define a special one here for the "no context"
  # version and generate the one with the context in the normal flow.
  defp casing(
         string,
         <<@sigma::utf8, rest::binary>>,
         :downcase = casing,
         :any = language,
         bytes_so_far,
         acc
       ) do
    bytes_so_far = bytes_so_far + @sigma_byte_size

    casing(string, rest, casing, language, bytes_so_far, [@lower_sigma | acc])
  end

  # Pass the character through since there is no casing data.
  # Optimize for ASCII bytes (byte value is less than 127)
  defp casing(string, <<byte::size(8), rest::binary>>, casing, :any = language, bytes_so_far, acc)
       when byte <= ?~ do
    bytes_so_far = bytes_so_far + 1

    casing(string, rest, casing, language, bytes_so_far, [byte | acc])
  end

  defp casing(string, <<next::utf8, rest::binary>>, casing, :any = language, bytes_so_far, acc) do
    next = <<next::utf8>>
    bytes_so_far = bytes_so_far + byte_size(next)

    casing(string, rest, casing, language, bytes_so_far, [next | acc])
  end

  # If the language version has no casing, use the default casing by
  # using the :any language.
  defp casing(string, rest, casing, _language, bytes_so_far, acc) do
    casing(string, rest, casing, :any, bytes_so_far, acc)
  end

  @doc false
  def unknown_locale_error(locale) do
    "Unknown locale #{inspect(locale)}"
  end
end
