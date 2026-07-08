defmodule Unicode.String.Trie do
  @moduledoc false

  # Thin wrapper over the `:btrie` NIF used to store and query the
  # segmentation dictionaries. Not part of the public API.

  def new(list) do
    :btrie.new(list)
  end

  def find_prefix(string, dictionary) do
    :btrie.find_prefix(string, dictionary)
  end

  def has_key(string, dictionary) do
    :btrie.is_key(string, dictionary)
  end
end
