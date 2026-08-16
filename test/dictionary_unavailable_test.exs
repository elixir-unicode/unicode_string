defmodule Unicode.String.DictionaryUnavailableTest do
  # Runs synchronously - it removes a dictionary from the priv directory and
  # from :persistent_term, both of which are global.
  use ExUnit.Case, async: false

  alias Unicode.String.Dictionary

  @app_name :unicode_string

  # The ICU dictionaries are downloaded with `mix unicode.string.download.dictionaries`
  # rather than shipped in the package, so a consumer can reasonably call a
  # dictionary locale without one being present. That must degrade to the
  # standard Unicode rules, not raise into the caller.

  setup do
    path = dictionary_path("khmer.txt")
    backup = path <> ".unavailable-test"
    dictionary = :persistent_term.get({@app_name, :km}, nil)

    File.rename!(path, backup)
    :persistent_term.erase({@app_name, :km})

    on_exit(fn ->
      File.rename!(backup, path)
      if dictionary, do: :persistent_term.put({@app_name, :km}, dictionary)
    end)

    :ok
  end

  defp dictionary_path(file_name) do
    @app_name
    |> :code.priv_dir()
    |> to_string()
    |> Path.join(["dictionaries/", file_name])
  end

  test "load/1 returns an error rather than raising" do
    assert {:error, message} = Dictionary.load(:km)
    assert message =~ "Could not read"
  end

  test "ensure_dictionary_loaded_if_available/1 returns an error" do
    assert {:error, message} = Dictionary.ensure_dictionary_loaded_if_available(:km)
    assert message =~ "No dictionary"
  end

  test "loaded?/1 is false and lookups find nothing rather than raising" do
    refute Dictionary.loaded?(:km)
    assert Dictionary.find_prefix("ជំរាប", :km) == :error
    refute Dictionary.has_key("ជំរាប", :km)
  end

  test "split/2 falls back to the standard rules" do
    string = "ជំរាបសួរ hello 100"
    segments = Unicode.String.split(string, break: :word, locale: :km, trim: true)

    assert "hello" in segments
    assert "100" in segments
    assert Enum.join(Unicode.String.split(string, break: :word, locale: :km)) == string
  end

  test "next/2 and stream/2 fall back to the standard rules" do
    assert {segment, rest} = Unicode.String.next("ជំរាបសួរ hello", break: :word, locale: :km)
    assert is_binary(segment) and is_binary(rest)

    assert Unicode.String.stream("ជំរាបសួរ hello", break: :word, locale: :km, trim: true)
           |> Enum.to_list()
           |> Enum.member?("hello")
  end

  test "line breaking falls back to the standard rules" do
    string = "ជំរាបសួរ hello"
    assert Enum.join(Unicode.String.split(string, break: :line, locale: :km)) == string
  end

  test "break/2 and splitter/2 return an error tuple" do
    assert {:error, message} = Unicode.String.break({"ជំរាប", "សួរ"}, break: :word, locale: :km)
    assert message =~ "No dictionary"

    assert {:error, _message} = Unicode.String.splitter("ជំរាបសួរ", break: :word, locale: :km)
  end
end
