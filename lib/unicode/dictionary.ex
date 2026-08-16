defmodule Unicode.String.Dictionary do
  @moduledoc """
  Implements basic dictionary functions for dictionary-based
  work break.

  This implementation supports dictionary-based word breaking for:

  * Chinese (`zh`, `zh-Hant`, `zh-Hans`, `zh-Hant-HK`, `yue`, `yue-Hans`) locales,
  * Japanese (`ja`) using the same dictionary as for Chinese,
  * Thai (`th`),
  * Lao (`lo`),
  * Khmer (`km`) and
  * Burmese (`my`).

  The dictionaries implemented are those used in the [CLDR](https://cldr.unicode.org) since
  they are under an open source license and also for consistency with
  [ICU](https://icu.unicode.org).

  A dictionary is applied only to runs of text written in the script(s) it covers -
  Han, Hiragana and Katakana for Chinese and Japanese, and the corresponding script
  for Thai, Lao, Khmer and Burmese. Text in any other script, such as Latin words or
  digits embedded in Japanese text, is broken by the standard
  [Unicode Segmentation](https://unicode.org/reports/tr29/) rules.

  Note that these dictionaries need to be downloaded with
  `mix unicode.string.download.dictionaries` prior to use. Each dictionary
  will be parsed and loaded into [persistent_term](https://www.erlang.org/doc/man/persistent_term)
  on demand. Note that each dictionary has a sizable memory footprint as measured
  by `:persistent_term.info/0`:

  | Dictionary  | Memory Mb   |
  | ----------- | ----------: |
  | Chinese     | 104.8       |
  | Thai        | 9.6         |
  | Lao         | 11.4        |
  | Khmer       | 38.8        |
  | Burmese     | 23.1        |

  """

  alias Unicode.String.Trie

  require Unicode.Set

  @app_name :unicode_string
  @dictionary_dir "dictionaries/"

  @dictionary_locales [
    :zh,
    :th,
    :lo,
    :my,
    :km,
    :ja,
    :"zh-Hant",
    :"zh-Hant-HK",
    :yue,
    :"yue-Hant",
    :"yue-Hans"
  ]

  @doc """
  Returns the locales that have a dictionary supporting
  word breaking.

  """
  def known_dictionary_locales do
    @dictionary_locales
  end

  @doc false
  def ensure_dictionary_loaded_if_available(locale) when locale in @dictionary_locales do
    require Logger

    with {:ok, locale} <- dictionary_locale(locale) do
      status =
        if dictionary = dictionary(locale) do
          {:ok, dictionary}
        else
          load(locale)
        end

      case status do
        {:ok, dictionary} ->
          {:ok, dictionary}

        _other ->
          message = "No dictionary for #{locale} found. Have you run `mix download.dictionaries`?"
          Logger.debug(message)
          {:error, message}
      end
    end
  end

  def ensure_dictionary_loaded_if_available(locale) do
    {:ok, "No dictionary for #{inspect(locale)} found"}
  end

  @doc false
  def load(locale) do
    with {:ok, locale} <- dictionary_locale(locale) do
      load_dictionary(locale)
    end
  end

  @doc false
  def loaded?(locale) do
    case dictionary_locale(locale) do
      {:ok, locale} -> :persistent_term.get({@app_name, locale}, false) && true
      _other -> false
    end
  end

  @doc false
  def dictionary(locale) when locale in @dictionary_locales do
    :persistent_term.get({@app_name, locale}, nil)
  end

  # The characters each dictionary is able to segment. These sets mirror the
  # ones used by the ICU dictionary break engines so that a dictionary is
  # applied only to text written in the script(s) it actually covers. Any other
  # text - Latin words, digits, punctuation - is segmented by the standard
  # Unicode word break rules.
  #
  # See https://github.com/unicode-org/icu/blob/main/icu4c/source/common/dictbe.cpp

  @doc false
  def dictionary_script?(codepoint, dictionary)

  # ー and ｰ are the prolonged sound marks and ﾞ and ﾟ the halfwidth voiced
  # sound marks. All four are Script=Common but only occur in Japanese text.
  def dictionary_script?(codepoint, :zh)
      when Unicode.Set.match?(
             codepoint,
             "[[:sc=Han:][:sc=Hiragana:][:sc=Katakana:]\\u30FC\\uFF70\\uFF9E\\uFF9F]"
           ) do
    true
  end

  def dictionary_script?(codepoint, :th)
      when Unicode.Set.match?(codepoint, "[[:sc=Thai:]&[:lb=SA:]]") do
    true
  end

  def dictionary_script?(codepoint, :lo)
      when Unicode.Set.match?(codepoint, "[[:sc=Lao:]&[:lb=SA:]]") do
    true
  end

  def dictionary_script?(codepoint, :km)
      when Unicode.Set.match?(codepoint, "[[:sc=Khmer:]&[:lb=SA:]]") do
    true
  end

  def dictionary_script?(codepoint, :my)
      when Unicode.Set.match?(codepoint, "[[:sc=Myanmar:]&[:lb=SA:]]") do
    true
  end

  def dictionary_script?(codepoint, _dictionary) when is_integer(codepoint) do
    false
  end

  # Splits `string` at the start of the first run of dictionary script,
  # returning `{text_before_the_run, run_and_everything_after_it}`. When there
  # is no dictionary script in `string` the second element is `""`.

  @doc false
  def split_at_dictionary_run(string, dictionary) do
    bytes = bytes_before_dictionary_run(string, dictionary, 0)
    <<before_run::binary-size(^bytes), from_run::binary>> = string
    {before_run, from_run}
  end

  defp bytes_before_dictionary_run(<<codepoint::utf8, rest::binary>> = string, dictionary, bytes) do
    if dictionary_script?(codepoint, dictionary) do
      bytes
    else
      bytes_before_dictionary_run(rest, dictionary, bytes + byte_size(string) - byte_size(rest))
    end
  end

  # Either the end of the string or not valid UTF-8. Either way there is no
  # dictionary script run left to split at.
  defp bytes_before_dictionary_run(string, _dictionary, bytes) do
    bytes + byte_size(string)
  end

  # These are called for every character of a dictionary script run so they
  # take the dictionary directly from :persistent_term. A dictionary that was
  # never downloaded is absent rather than empty, hence the explicit default.

  @doc false
  def has_key(string, locale) do
    with {:ok, locale} <- dictionary_locale(locale) do
      case :persistent_term.get({@app_name, locale}, nil) do
        nil -> false
        dictionary -> Trie.has_key(string, dictionary)
      end
    end
  end

  @doc false
  def find_prefix(string, locale) do
    with {:ok, locale} <- dictionary_locale(locale) do
      case :persistent_term.get({@app_name, locale}, nil) do
        nil -> :error
        dictionary -> Trie.find_prefix(string, dictionary)
      end
    end
  end

  @doc false
  @dialyzer {:nowarn_function, load_dictionary: 1}
  defp load_dictionary(:zh), do: load_dictionary(:zh, "chinese_japanese.txt")
  defp load_dictionary(:ja), do: load_dictionary(:zh)
  defp load_dictionary(:lo), do: load_dictionary(:lo, "lao.txt")
  defp load_dictionary(:th), do: load_dictionary(:th, "thai.txt")
  defp load_dictionary(:my), do: load_dictionary(:my, "burmese.txt")
  defp load_dictionary(:km), do: load_dictionary(:km, "khmer.txt")

  @comment_marker ["#", " #", "  #", "\uFEFF #"]

  defp load_dictionary(locale, file_name) do
    require Logger

    with {:ok, contents} <- read_dictionary(file_name) do
      trie = contents |> dictionary_entries() |> Trie.new()
      :ok = :persistent_term.put({@app_name, locale}, trie)
      trie = :persistent_term.get({@app_name, locale})

      # Logger.debug("[unicode_string] Loaded word break dictionary for locale #{inspect locale}")
      {:ok, trie}
    end
  end

  defp dictionary_entries(contents) do
    contents
    |> String.split("\n")
    |> Enum.reject(&(String.starts_with?(&1, @comment_marker) or String.length(&1) == 0))
    |> Enum.map(&dictionary_entry/1)
  end

  defp dictionary_entry(line) do
    case String.split(line, "\t") do
      [word] -> word
      [word, value] -> {word, String.to_integer(value)}
    end
  end

  # A dictionary that has not been downloaded is not an error the caller
  # should have to rescue - word breaking falls back to the standard
  # Unicode rules - so the read returns an error rather than raising.

  defp read_dictionary(file_name) do
    priv_dir = :code.priv_dir(@app_name) |> to_string
    path = Path.join(priv_dir, [@dictionary_dir, file_name])

    case File.read(path) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, reason} ->
        {:error, "Could not read #{inspect(path)}: #{:file.format_error(reason)}"}
    end
  end

  @doc false
  def dictionary_locale(:zh), do: {:ok, :zh}
  def dictionary_locale(:"zh-Hant"), do: {:ok, :zh}
  def dictionary_locale(:"zh-Hant-HK"), do: {:ok, :zh}
  def dictionary_locale(:yue), do: {:ok, :zh}
  def dictionary_locale(:"yue-Hant"), do: {:ok, :zh}
  def dictionary_locale(:"yue-Hans"), do: {:ok, :zh}

  def dictionary_locale(:lo), do: {:ok, :lo}
  def dictionary_locale(:my), do: {:ok, :my}
  def dictionary_locale(:th), do: {:ok, :th}
  def dictionary_locale(:km), do: {:ok, :km}
  def dictionary_locale(:ja), do: {:ok, :zh}
  def dictionary_locale(%{language: language}), do: dictionary_locale(language)
  def dictionary_locale(language), do: {:error, "No dictionary for #{inspect(language)} found."}
end
