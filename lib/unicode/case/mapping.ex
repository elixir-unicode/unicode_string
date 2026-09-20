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
  #
  # Each is compiled here rather than written as `~r/#{@pattern}/u` at the point
  # of use. An interpolated sigil is not a literal, so it compiles its pattern
  # on every evaluation, and these patterns are large — expanding the property
  # sets gives roughly 9KB each. Compiling one costs about 107us against 3us to
  # match with it already compiled, and a contextual rule evaluates one or two
  # per character.
  @final_sigma_before Unicode.Regex.expand_regex("\\p{cased}(\\p{Case_Ignorable})*")
  @final_sigma_after Unicode.Regex.expand_regex("(\\p{Case_Ignorable})*\\p{cased}")

  @after_soft_dotted Unicode.Regex.expand_regex("[\\p{Soft_Dotted}]([^\\p{ccc=230}\\p{ccc=0}])*")
  @more_above Unicode.Regex.expand_regex("[^\\p{ccc=230}\\p{ccc=0}]*[\\p{ccc=230}]")
  @before_dot Unicode.Regex.expand_regex("([^\\p{ccc=230}\\p{ccc=0}])*[\u0307]")
  @after_i Unicode.Regex.expand_regex("[I]([^\\p{ccc=230}\\p{ccc=0}])*")

  @final_sigma_before_regex Regex.compile!(@final_sigma_before, "u")
  @final_sigma_after_regex Regex.compile!(@final_sigma_after, "u")
  @after_soft_dotted_regex Regex.compile!(@after_soft_dotted, "u")
  @more_above_regex Regex.compile!(@more_above, "u")
  @before_dot_regex Regex.compile!(@before_dot, "u")
  @after_i_regex Regex.compile!(@after_i, "u")

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

    casing, codepoint, replace, _language, "final_sigma" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)
      replacement = :unicode.characters_to_binary(replace)

      # Sigma is the only contextual rule defined for `:any`, and no locale
      # overrides it, so the clause matches every locale. Restricting it to
      # `:any` would send Greek text to the no-rule fallback, which cases one
      # character at a time and cannot see whether the sigma ends a word.
      defp casing(
             string,
             <<@sigma::utf8, rest::binary>>,
             unquote(casing),
             locale,
             bytes_so_far,
             acc
           ) do
        <<prior::binary-size(^bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(@final_sigma_before_regex, prior) &&
             !Regex.match?(@final_sigma_after_regex, rest) do
          casing(string, rest, unquote(casing), locale, bytes_so_far, [
            unquote(replacement) | acc
          ])
        else
          casing(string, rest, unquote(casing), locale, bytes_so_far, [
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
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        # `Before_Dot` asks whether a combining dot above *follows* this
        # character, so the test is against the remainder of the string. The
        # `After_*` contexts below are the lookbehind cases and test `prior`.
        if Regex.match?(@before_dot_regex, rest) do
          # The accumulator starts empty here. Passing `acc` would fold every
          # character mapped so far into `this`, which is then prepended to
          # `acc` again, duplicating the whole prefix of the string.
          this =
            casing(
              <<unquote(codepoint)::utf8>>,
              <<unquote(codepoint)::utf8>>,
              unquote(casing),
              :any,
              0,
              []
            )

          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [this | acc])
        else
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
            unquote(replacement) | acc
          ])
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

        if Regex.match?(@more_above_regex, rest) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
            unquote(replacement) | acc
          ])
        else
          # The accumulator starts empty here. Passing `acc` would fold every
          # character mapped so far into `this`, which is then prepended to
          # `acc` again, duplicating the whole prefix of the string.
          this =
            casing(
              <<unquote(codepoint)::utf8>>,
              <<unquote(codepoint)::utf8>>,
              unquote(casing),
              :any,
              0,
              []
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
        <<prior::binary-size(^bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(@after_soft_dotted_regex, prior) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
            unquote(replacement) | acc
          ])
        else
          # The accumulator starts empty here. Passing `acc` would fold every
          # character mapped so far into `this`, which is then prepended to
          # `acc` again, duplicating the whole prefix of the string.
          this =
            casing(
              <<unquote(codepoint)::utf8>>,
              <<unquote(codepoint)::utf8>>,
              unquote(casing),
              :any,
              0,
              []
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
        <<prior::binary-size(^bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(@after_i_regex, prior) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [
            unquote(replacement) | acc
          ])
        else
          # The accumulator starts empty here. Passing `acc` would fold every
          # character mapped so far into `this`, which is then prepended to
          # `acc` again, duplicating the whole prefix of the string.
          this =
            casing(
              <<unquote(codepoint)::utf8>>,
              <<unquote(codepoint)::utf8>>,
              unquote(casing),
              :any,
              0,
              []
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

  ### Arguments

  * `string` is any `t:String.t/0`.

  * `language` is a language atom such as `:tr` or `:el`. The default is `:any`,
    which applies the base Unicode algorithm with no locale tailoring. The
    languages with tailored casing are returned by
    `Unicode.String.special_casing_locales/0`.

  ### Returns

  * The upper cased string.

  ### Examples

      iex> Unicode.String.Case.Mapping.upcase("the quick brown fox")
      "THE QUICK BROWN FOX"

      iex> Unicode.String.Case.Mapping.upcase("Diyarbakır", :tr)
      "DİYARBAKIR"

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

  ### Arguments

  * `string` is any `t:String.t/0`.

  * `language` is a language atom such as `:tr` or `:el`. The default is `:any`,
    which applies the base Unicode algorithm with no locale tailoring.

  ### Returns

  * The lower cased string.

  ### Examples

      iex> Unicode.String.Case.Mapping.downcase("THE QUICK BROWN FOX")
      "the quick brown fox"

      iex> Unicode.String.Case.Mapping.downcase("ὈΔΥΣΣΕΎΣ", :el)
      "ὀδυσσεύς"

  """
  def downcase(string, language \\ :any)

  def downcase(string, language) when is_atom(language) do
    casing(string, string, :downcase, language, 0, [])
  end

  @doc """
  Apply the Unicode title case algorithm.

  Only the first character is cased; the remainder of the string is lower cased.

  ### Arguments

  * `string` is any `t:String.t/0`.

  * `language` is a language atom such as `:nl`. The default is `:any`, which
    applies the base Unicode algorithm with no locale tailoring.

  ### Returns

  * The title cased string.

  ### Examples

      iex> Unicode.String.Case.Mapping.titlecase("the quick brown fox")
      "The quick brown fox"

      iex> Unicode.String.Case.Mapping.titlecase("ijsselmeer", :nl)
      "IJsselmeer"

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
  # they upcase to a dotted-capital-I, and `I` and `J` from the lower casing
  # ranges since Lithuanian gives them a dot above when an accent follows and
  # Turkish and Azeri lower `I` to a dotless one.

  defp casing(
         string,
         <<byte::size(8), rest::binary>>,
         :downcase = casing,
         language,
         bytes_so_far,
         acc
       )
       when byte >= ?A and byte <= ?Z and byte != ?I and byte != ?J do
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
       when byte != ?I and byte != ?J and byte <= ?~ do
    casing(string, rest, casing, language, bytes_so_far + 1, [byte | acc])
  end

  # Generate the mapping functions

  # `SpecialCasing.txt` leaves a mapping field blank when the character is
  # *removed* in that context, which the parsed data reports as `nil`. A `nil`
  # on a `:special` entry is therefore a mapping to the empty string, not an
  # absent mapping. Three entries rely on this: the combining dot above is
  # dropped when lower casing after a Turkish or Azeri `I`, and when upper or
  # title casing after a Lithuanian soft-dotted letter.
  mapping = fn
    nil, %{type: :special} -> ~c""
    nil, _casing -> nil
    mapping, _casing -> mapping
  end

  # `?I` and `?J` are the ASCII characters with language-specific mappings, so
  # they are excluded from the ASCII fast path above and handled here instead.
  cased_ascii = [?i, ?I, ?j, ?J]

  fields = [{:upcase, :upper}, {:downcase, :lower}, {:titlecase, :title}]

  in_scope = fn codepoint, replacement ->
    replacement && replacement != codepoint &&
      (codepoint in cased_ascii or codepoint > ?~)
  end

  # Only a rule that reads the text around the character needs a function clause
  # of its own; there are nine of those. The rest are a plain substitution keyed
  # by casing, language and code point, so they go in one map rather than one
  # clause each. As clauses they were 4,776 of them and took 47 seconds to
  # compile, which was the whole cost of building this library.
  #
  # Sigma is excluded for `:downcase`: it is the one code point with both a
  # contextual and an uncontextual rule for `:any`, and its uncontextual case is
  # handled by a clause of its own further down.
  @simple_mappings (for entry <- Utils.casing_in_order(),
                        is_nil(entry.context),
                        {casing, field} <- fields,
                        replacement = mapping.(Map.fetch!(entry, field), entry),
                        in_scope.(entry.codepoint, replacement),
                        not (casing == :downcase and entry.codepoint == @sigma),
                        into: %{} do
                      {{casing, entry.language, entry.codepoint},
                       :unicode.characters_to_binary(replacement)}
                    end)

  for entry <- Utils.casing_in_order(),
      entry.context,
      {casing, field} <- fields,
      replacement = mapping.(Map.fetch!(entry, field), entry),
      in_scope.(entry.codepoint, replacement) do
    define_casing_function.(casing, entry.codepoint, replacement, entry.language, entry.context)
  end

  # Every uncontextual mapping, in one clause. `remaining` and `rest` bracket the
  # character just matched, so its width comes from their sizes rather than from
  # re-encoding the code point.
  defp casing(
         string,
         <<codepoint::utf8, rest::binary>> = remaining,
         casing,
         language,
         bytes_so_far,
         acc
       )
       when is_map_key(@simple_mappings, {casing, language, codepoint}) do
    replacement = :erlang.map_get({casing, language, codepoint}, @simple_mappings)
    bytes_so_far = bytes_so_far + byte_size(remaining) - byte_size(rest)

    casing(string, rest, casing, language, bytes_so_far, [replacement | acc])
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

  # If the language has no clause for this character, case just this character
  # with the default rules and then carry on in the original language.
  #
  # Re-dispatching the whole remainder as `:any` would drop the language for
  # everything after the first character it has no rule for. Lithuanian `i`
  # followed by a combining dot above is the case that shows it: `i` has no
  # Lithuanian clause, so the dot that follows would be cased as `:any` and its
  # Lithuanian rule never applied.
  defp casing(string, <<next::utf8, rest::binary>>, casing, language, bytes_so_far, acc) do
    character = <<next::utf8>>
    cased = casing(character, character, casing, :any, 0, [])

    casing(string, rest, casing, language, bytes_so_far + byte_size(character), [cased | acc])
  end

  @doc false
  def unknown_locale_error(locale) do
    "Unknown locale #{inspect(locale)}"
  end
end
