defmodule Unicode.String.Dictionary do
  @moduledoc false

  alias Unicode.String.Trie

  @app_name :unicode_string
  @dictionary_dir "dictionaries/"
  @dictionary_locales [:zh, :th, :lo, :my, :km, :ja, :"zh-Hant", :"zh-Hant-HK"]

  def known_dictionary_locales do
    @dictionary_locales
  end

  def ensure_dictionary_loaded_if_available(locale) when locale in @dictionary_locales do
    with {:ok, locale} <- dictionary_locale(locale) do
      if dictionary = dictionary(locale) do
        {:ok, dictionary}
      else
        load(locale)
      end
    end
  end

  def ensure_dictionary_loaded_if_available(locale) do
    {:ok, "No dictionary for #{inspect locale} found"}
  end

  def load(locale) do
    with {:ok, locale} <- dictionary_locale(locale) do
      load_dictionary(locale)
    end
  end

  def is_loaded(locale) do
    with {:ok, locale} <- dictionary_locale(locale) do
      :persistent_term.get({@app_name, locale}, false) && true
    else
      _other -> false
    end
  end

  def dictionary(locale) when locale in @dictionary_locales do
    :persistent_term.get({@app_name, locale}, nil)
  end

  @doc false
  def has_key(string, locale) do
    with {:ok, locale} <- dictionary_locale(locale) do
      dictionary = :persistent_term.get({@app_name, locale})
      Trie.has_key(string, dictionary)
    end
  end

  @doc false
  def find_prefix(string, locale) do
    with {:ok, locale} <- dictionary_locale(locale) do
      dictionary = :persistent_term.get({@app_name, locale})
      Trie.find_prefix(string, dictionary)
    end
  end

  defp load_dictionary(:zh), do: load_dictionary(:zh, "chinese_japanese.txt")
  defp load_dictionary(:ja), do: load_dictionary(:zh)
  defp load_dictionary(:lo), do: load_dictionary(:lo, "lao.txt")
  defp load_dictionary(:th), do: load_dictionary(:th, "thai.txt")
  defp load_dictionary(:my), do: load_dictionary(:my, "burmese.txt")
  defp load_dictionary(:km), do: load_dictionary(:km, "khmer.txt")

  defp load_dictionary(locale, file_name) do
    require Logger

    trie =
      file_name
      |> read_dictionary()
      |> String.split("\n")
      |> Enum.reject(&String.starts_with?(&1, ["#", " #", "  #", "\uFEFF #"]))
      |> Enum.reject(&(String.length(&1) == 0))
      |> Enum.map(fn line ->
        case String.split(line, "\t") do
          [word] -> word
          [word, value] -> {word, String.to_integer(value)}
        end
      end)
      |> Trie.new()

    :ok = :persistent_term.put({@app_name, locale}, trie)
    Logger.debug("[unicode_string] Loaded word break dictionary for locale #{inspect locale}")
    {:ok, trie}
  end

  defp read_dictionary(file_name) do
    priv_dir = :code.priv_dir(@app_name) |> to_string
    path = Path.join(priv_dir, [@dictionary_dir, file_name])
    File.read!(path)
  end

  def dictionary_locale(:zh), do: {:ok, :zh}
  def dictionary_locale(:"zh-Hant"), do: {:ok, :zh}
  def dictionary_locale(:"zh-Hant-HK"), do: {:ok, :zh}
  def dictionary_locale(:lo), do: {:ok, :lo}
  def dictionary_locale(:my), do: {:ok, :my}
  def dictionary_locale(:th), do: {:ok, :th}
  def dictionary_locale(:km), do: {:ok, :km}
  def dictionary_locale(:ja), do: {:ok, :zh}
  def dictionary_locale(%{language: language}), do: dictionary_locale(language)
  def dictionary_locale(language), do: {:error, "No dictionary for #{inspect language} found."}

end