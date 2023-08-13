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

  There are many other casing rules that are not currently implemented:

  * Titlecasing of IJ at the start of words in Dutch.
  * Removal of accents when upper casing letters in Greek.
  * Titlecasing of second or subsequent letters in words in orthographies that include
    caseless letters such as apostrophes.
  * Uppercasing of U+00DF `ß` latin small letter sharp `s` to U+1E9E `ẞ` latin capital letter
    sharp `s`.

  """

  @sigma 0x03A3
  @lower_sigma 0x03C3
  @sigma_byte_size byte_size(<<@sigma::utf8>>)

  # See table Table 3-17 of https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf
  # for details of the contexts

  @final_sigma_before Unicode.Regex.compile!("\\p{cased}(\\p{Case_Ignorable})*")
  @final_sigma_after Unicode.Regex.compile!("(\\p{Case_Ignorable})*\\p{cased}")

  @after_soft_dotted Unicode.Regex.compile!("[\\p{Soft_Dotted}]([^\\p{ccc=230}\\p{ccc=0}])*")
  @more_above Unicode.Regex.compile!("[^\\p{ccc=230}\\p{ccc=0}]*[\\p{ccc=230}]")
  @before_dot Unicode.Regex.compile!("([^\\p{ccc=230}\\p{ccc=0}])*[\u0307]")
  @after_i Unicode.Regex.compile!("[I]([^\\p{ccc=230}\\p{ccc=0}])*")

  utf8_bytes_for_codepoint = fn codepoint ->
    byte_size(<<codepoint::utf8>>)
  end

  # Attempting to avoid string
  define_casing_function = fn
    casing, codepoint, replace, language, nil ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)

      defp casing(string, <<unquote(codepoint)::utf8, rest::binary>>, unquote(casing), unquote(language), bytes_so_far, acc) do
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)
        casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [unquote(replace) | acc])
      end

    casing, codepoint, replace, language, "final_sigma" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)

      defp casing(string, <<@sigma::utf8, rest::binary>>, unquote(casing), unquote(language), bytes_so_far, acc) do
        <<prior::binary-size(bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(@final_sigma_before, prior) && !Regex.match?(@final_sigma_after, rest) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [unquote(replace) | acc])
        else
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [@lower_sigma | acc])
        end
      end

    casing, codepoint, replace, language, "not_before_dot" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)

      defp casing(string, <<unquote(codepoint)::utf8, rest::binary>>, unquote(casing), unquote(language), bytes_so_far, acc) do
        <<prior::binary-size(bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if !Regex.match?(@before_dot, prior) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [unquote(replace) | acc])
        else
          this = casing(<<unquote(codepoint)::utf8>>, <<unquote(codepoint)::utf8>>, unquote(casing), :any, 0, acc)
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [this | acc])
        end
      end

    casing, codepoint, replace, language, "more_above" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)

      defp casing(string, <<unquote(codepoint)::utf8, rest::binary>>, unquote(casing), unquote(language), bytes_so_far, acc) do
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(@more_above, rest) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [unquote(replace) | acc])
        else
          this = casing(<<unquote(codepoint)::utf8>>, <<unquote(codepoint)::utf8>>, unquote(casing), :any, 0, acc)
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [this | acc])
        end
      end

    casing, codepoint, replace, language, "after_soft_dotted" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)

      defp casing(string, <<unquote(codepoint)::utf8, rest::binary>>, unquote(casing), unquote(language), bytes_so_far, acc) do
        <<prior::binary-size(bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(@after_soft_dotted, prior) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [unquote(replace) | acc])
        else
          this = casing(<<unquote(codepoint)::utf8>>, <<unquote(codepoint)::utf8>>, unquote(casing), :any, 0, acc)
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [this | acc])
        end
      end

    casing, codepoint, replace, language, "after_i" ->
      codepoint_bytes = utf8_bytes_for_codepoint.(codepoint)

      defp casing(string, <<unquote(codepoint)::utf8, rest::binary>>, unquote(casing), unquote(language), bytes_so_far, acc) do
        <<prior::binary-size(bytes_so_far), _remaining::binary>> = string
        bytes_so_far = bytes_so_far + unquote(codepoint_bytes)

        if Regex.match?(@after_i, prior) do
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [unquote(replace) | acc])
        else
          this = casing(<<unquote(codepoint)::utf8>>, <<unquote(codepoint)::utf8>>, unquote(casing), :any, 0, acc)
          casing(string, rest, unquote(casing), unquote(language), bytes_so_far, [this | acc])
        end
      end
  end

  @doc """
  Apply to Unicode upper case algorithm.

  """
  def upcase(string, language \\ :any)

  def upcase(string, language) when is_atom(language) do
    casing(string, string, :upcase,language, 0, [])
  end

  @doc """
  Apply to Unicode upper case algorithm.

  """
  def downcase(string, language \\ :any)

  def downcase(string, language) when is_atom(language) do
    casing(string, string, :downcase, language, 0, [])
  end

  @doc """
  Apply to Unicode title case algorithm.

  """
  def titlecase(string, language \\ :any)

  def titlecase(<<first::utf8, rest::binary>>, language) when is_atom(language) do
    casing(<<first::utf8>>, <<first::utf8>>, :titlecase, language, 0, []) <> downcase(rest, language)
  end

  # Generate the mapping functions

  for %{upper: upper, context: context} = casing <- Unicode.Utils.casing_in_order(), !is_nil(upper) do
    %{codepoint: codepoint, language: language} = casing

    define_casing_function.(:upcase, codepoint, upper, language, context)
  end

  for %{lower: lower, context: context} = casing <- Unicode.Utils.casing_in_order(), !is_nil(lower) do
    %{codepoint: codepoint, language: language} = casing

    # Special casing for capital sigma with no context.
    # see the default implementations of casing/5 at the
    # end of this file. Don't generate a function clause for
    # this codepoint here.
    unless codepoint == @sigma and is_nil(context) do
      define_casing_function.(:downcase, codepoint, lower, language, context)
    end
  end

  for %{title: title, context: context} = casing <- Unicode.Utils.casing_in_order(), !is_nil(title) do
    %{codepoint: codepoint, language: language} = casing

    define_casing_function.(:titlecase, codepoint, title, language, context)
  end

  # End of string, return accumulator
  defp casing(_string, "", _casing, _language, _bytes_so_far, acc) do
    acc
    |> Enum.reverse()
    |> :unicode.characters_to_binary()
  end

  # Special case for Greek sigma when no context. This is the only codepoint
  # that has two cases for the language :any. One case with "final_sigma" context
  # and one with no context. This means we can't generate two distinct function
  # clauses for casing/5 so we define a special one here for the "no context"
  # version and generate the one with the context in the normal flow.
  defp casing(string, <<@sigma::utf8, rest::binary>>, :downcase = casing, :any = language, bytes_so_far, acc) do
    bytes_so_far = bytes_so_far + @sigma_byte_size

    casing(string, rest, casing, language, bytes_so_far, [@lower_sigma | acc])
  end

  # Pass the character through since there is no casing data.
  defp casing(string, <<next::utf8, rest::binary>>, casing, :any = language, bytes_so_far, acc) do
    bytes_so_far = bytes_so_far + byte_size(<<next::utf8>>)

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