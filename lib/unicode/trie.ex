defmodule Unicode.String.Trie do
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