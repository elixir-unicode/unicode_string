defmodule Unicode.String.Case.Folding do
  @moduledoc """
  Implements the Unicode Case Folding algorithm.

  The intention of case folding is to facilitate
  case-insensitive string comparisons. It is not
  intended to be a general purpose transformation.

  Although case folding does generally use lower
  case as its normal form, it is not true for
  all scripts and codepoints.  Therefore case
  folding should not be used as an alternative
  to `String.downcase/1`.

  """

  @turkic_languages [:tr, :az]
  @fold_status [:turkic, :common, :full]

  @doc """
  Case fold a string.

  Returns a string after applying the Unicode
  Case Folding algorithm.

  Case folding is intended to suport case
  insensitve string comparisons such as that
  implemented by `Unicode.String.equals_ignoring_case?/2` which
  calls this function on its parameters.

  ### Arguments

  * `string` is any `String.t()`

  * `mode or language tag` is either the atoms `:turkic` or `nil`
    or a map that includes the key `:language` with a value that
    is a lowercase atom representing an [ISO 639-1](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)
    language code. The [CLDR language tag](https://hexdocs.pm/ex_cldr/Cldr.LanguageTag.html) which is defined
    as part of the [ex_cldr](https://hex.pm/packages/ex_cldr) is one
    such example. See [Cldr.validate_locale/2](https://hexdocs.pm/ex_cldr/Cldr.html#validate_locale/2)
    for further information. The default is `nil`.

  ### Returns

    * The case folded string

  ### Notes

  * No normalization is applied to the
    string on either input or output.

  * Case folding does not apply any transformation
    to accented characters. `"ü" will not case fold
    to `"u"` for example.

  ### Examples

      iex> Unicode.String.Case.Folding.fold("THIS")
      "this"

      iex> Unicode.String.Case.Folding.fold("grüßen")
      "grüssen"

      iex(13)> Unicode.String.Case.Folding.fold("I")
      "i"

      # Turkic languages such as Turkish and Azerbaijani have
      # a dotless lower case "i"
      iex> Unicode.String.Case.Folding.fold("I", :turkic)
      "ı"

      iex> Unicode.String.Case.Folding.fold("I", %{language: :az})
      "ı"

  """
  def fold(string) when is_binary(string) do
    fold(string, :full, nil)
  end

  def fold(string, %{language: language}) when language in @turkic_languages do
    fold(string, :full, :turkic)
  end

  def fold(string, language) when language in @turkic_languages do
    fold(string, :full, :turkic)
  end

  def fold(string, %{language: _language}) do
    fold(string, :full, nil)
  end

  def fold(string, :turkic) when is_binary(string) do
    fold(string, :full, :turkic)
  end

  def fold(string, _other) when is_binary(string) do
    fold(string, :full, nil)
  end

  for [status, from, to] <- Unicode.Utils.case_folding(), status in @fold_status do
    to = if is_list(to), do: List.to_string(to), else: List.to_string([to])

    case status do
      :turkic ->
        defp fold(<<unquote(from)::utf8, rest::binary>>, _status, :turkic) do
          <<unquote(to), fold(rest, unquote(status))::binary>>
        end

      :common ->
        defp fold(<<unquote(from)::utf8, rest::binary>>, status, mode) do
          <<unquote(to), fold(rest, status, mode)::binary>>
        end

      :full ->
        defp fold(<<unquote(from)::utf8, rest::binary>>, unquote(status), mode) do
          <<unquote(to), fold(rest, unquote(status), mode)::binary>>
        end
    end
  end

  defp fold(<<from::utf8, rest::binary>>, status, mode) do
    <<from::utf8, fold(rest, status, mode)::binary>>
  end

  defp fold("", _, _) do
    ""
  end
end
