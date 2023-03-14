# Unicode String

Adds functions supporting some string algorithms in the Unicode standard:

* The [Unicode Case Folding](https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf) algorithm to provide case-independent equality checking irrespective of language or script with `Unicode.String.fold/2` and `Unicode.String.equals_ignoring_case?/2`

* The [Unicode Segmentation](https://unicode.org/reports/tr29/) algorithm to detect, break, split or stream strings into grapheme clusters, words, sentences and line break points.

* The [Unicode Line Breaking](https://www.unicode.org/reports/tr14/) algorithm to determine line breaks (as in breaks where word-wrapping would be acceptable).

## Casing

The [Unicode Case Folding](https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf) algorithm defines how to perform case folding. This allows comparison of strings in a case-insensitive fashion. It does not define the means to compare ignoring diacritical marks (accents). Some examples follow, for details see:

* `Unicode.String.fold/2`
* `Unicode.String.equals_ignoring_case?/3`

```elixir
iex> Unicode.String.equals_ignoring_case? "ABC", "abc"
true

iex> Unicode.String.equals_ignoring_case? "beißen", "beissen"
true

iex> Unicode.String.equals_ignoring_case? "grüßen", "grussen"
false
```
## Segmentation

The [Unicode Segmentation](https://unicode.org/reports/tr29/) annex details the algorithm to be applied with segmenting text (Elixir strings) into words, sentences, graphemes and line breaks. Some examples follow, for details see:

* `Unicode.String.split/2`
* `Unicode.String.break?/2`
* `Unicode.String.break/2`
* `Unicode.String.splitter/2`
* `Unicode.String.next/2`
* `Unicode.String.stream/2`

```elixir
# Split text at a word boundary.
iex> Unicode.String.split "This is a sentence. And another.", break: :word
["This", " ", "is", " ", "a", " ", "sentence", ".", " ", "And", " ", "another", "."]

# Split text at a word boundary but omit any whitespace
iex> Unicode.String.split "This is a sentence. And another.", break: :word, trim: true
["This", "is", "a", "sentence", ".", "And", "another", "."]

# Split text at a sentence boundary.
iex> Unicode.String.split "This is a sentence. And another.", break: :sentence
["This is a sentence. ", "And another."]

# By default, common abbreviations are suppressed (ie
# the do not cause a break)
iex> Unicode.String.split "No, I don't have a Ph.D. but I don't think it matters.", break: :word, trim: true
["No", ",", "I", "don't", "have", "a", "Ph.D", ".", "but", "I", "don't",
 "think", "it", "matters", "."]

iex> Unicode.String.split "No, I don't have a Ph.D. but I don't think it matters.", break: :sentence, trim: true
["No, I don't have a Ph.D. but I don't think it matters."]

# Break suppressions are locale sensitive.
iex> Unicode.String.Segment.known_locales
["de", "el", "en", "en-US", "en-US-POSIX", "es", "fi", "fr", "it", "ja", "pt",
 "root", "ru", "sv", "zh", "zh-Hant"]

iex> Unicode.String.split "Non, c'est M. Dubois.", break: :word, trim: true, locale: "fr"
["Non", ",", "c'est", "M", ".", "Dubois", "."]

# Note that break: :line does NOT mean split the string
# at newlines. It splits the string where a line break would be
# acceptable. This is very useful for calculating where
# to perform word-wrap on some text.
iex> Unicode.String.split "This is a sentence. And another.", break: :line
["This ", "is ", "a ", "sentence. ", "And ", "another."]
```

### Streaming

Segmentation can also be streamed using `Unicode.String.stream/2`. For large strings this may improve memory usage since the intermediate segments will garbage collected when they fall out of scope.

```elixir
iex> Enum.to_list Unicode.String.stream("this is a set of words", trim: true)                       ["this", "is", "a", "set", "of", "words"]

iex> Enum.map Unicode.String.stream("this is a set of words", trim: true),
...>   fn word -> %{word: word, length: String.length(word)} end
[
  %{length: 4, word: "this"},
  %{length: 2, word: "is"},
  %{length: 1, word: "a"},
  %{length: 3, word: "set"},
  %{length: 2, word: "of"},
  %{length: 5, word: "words"}
]
```

## Installation

The package can be installed by adding `:unicode_string` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:unicode_string, "~> 1.0"}
  ]
end
```

