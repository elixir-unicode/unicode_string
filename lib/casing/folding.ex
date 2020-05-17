defmodule Unicode.String.Case.Folding do
  @moduledoc """
  Implements the Unicode Case Folding algorithm.

  The intention of case folding is to faciliate
  case-insensitive string comparisons. It is not
  intended to be a general purpose transformation.

  Although case folding does generally use lower
  case as its normal form, it is not true for
  all scripts and codepoints.  Therefore case
  folding should not be used as an alternative
  to `String.downcase/1`.

  """

  @doc """
  Case fold a string.

  Returns a string after applying the Unicode
  Case Folding algorithm.

  It is recommended to call
  `Unicode.String.fold/1,2` instead of this
  function.

  ## Arguments

  * `string` is any `String.t()`

  * `type` is one of `:full` or `:simple`.
    The default is `:full`.

  * `mode` is either `:turkic` or `nil`.
    The default is `nil`.

  ## Returns

    * The case folded string

  ## Notes

  * No normalization is applied to the
    string on either input or output.

  """
  def fold(string) when is_binary(string) do
    fold(string, :full, nil)
  end

  def fold(string, :turkic) when is_binary(string) do
    fold(string, :full, :turkic)
  end

  def fold(string, type) when is_binary(string) and type in [:simple, :full] do
    fold(string, type, nil)
  end

  for [status, from, to] <- Unicode.Utils.case_folding do
    to =
      if is_list(to), do: List.to_string(to), else: List.to_string([to])

    case status do
      :turkic ->
        defp fold(<< unquote(from) :: utf8, rest :: binary >>, _status, :turkic) do
          << unquote(to), fold(rest, unquote(status)) :: binary >>
        end

      :common ->
        defp fold(<< unquote(from) :: utf8, rest :: binary >>, status, mode) do
          << unquote(to), fold(rest, status, mode) :: binary >>
        end

      other ->
        defp fold(<< unquote(from) :: utf8, rest :: binary >>, unquote(other), mode) do
          << unquote(to), fold(rest, unquote(status), mode) :: binary >>
        end
    end
  end

  defp fold(<< from :: utf8, rest :: binary >>, status, mode) do
    << from, fold(rest, status, mode) :: binary >>
  end

  defp fold("", _, _) do
    ""
  end
end