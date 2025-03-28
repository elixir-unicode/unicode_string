# Unicode String

![Build status](https://github.com/elixir-unicode/unicode_string/actions/workflows/ci.yml/badge.svg)
[![Hex.pm](https://img.shields.io/hexpm/v/unicode_string.svg)](https://hex.pm/packages/unicode_string)
[![Hex.pm](https://img.shields.io/hexpm/dw/unicode_string.svg?)](https://hex.pm/packages/unicode_string)
[![Hex.pm](https://img.shields.io/hexpm/l/unicode_string.svg)](https://hex.pm/packages/unicode_string)

Adds functions supporting some string algorithms in the Unicode standard. For example:

* The [Unicode Case Folding](https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf) algorithm to provide case-independent equality checking irrespective of language or script with `Unicode.String.fold/2` and `Unicode.String.equals_ignoring_case?/2`

* The [Unicode Code Mapping](https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf) algorithm that implements locale-aware `Unicode.String.upcase/2`, `Unicode.String.downcase/2` and `Unicode.String.titlecase/2`.

* The [Unicode Segmentation](https://unicode.org/reports/tr29/) algorithm to detect, break, split or stream strings into grapheme clusters, words and sentences.

* The [Unicode Line Breaking](https://www.unicode.org/reports/tr14/) algorithm to determine line breaks (breaks meaning where word-wrapping would be acceptable).

## Installation

The package can be installed by adding `:unicode_string` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:unicode_string, "~> 1.0"},
    ...
  ]
end
```

Then run `mix dep.get`.

> #### Word Break Dictionary Download {: .info}
>
> If you plan to perform word break segmentation on Chinese, Japanese, Lao,
> Burmese, Thai or Khmer languages you will need to download the word break dictionaries
> by running `mix unicode.string.download.dictionaries`.

## Casing

### Case Folding

The [Unicode Case Folding](https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf) algorithm defines how to perform case folding. This allows comparison of strings in a case-insensitive fashion. It does not define the means to compare ignoring diacritical marks (accents). Some examples follow, for details see:

* `Unicode.String.fold/2`
* `Unicode.String.equals_ignoring_case?/3`

> #### Note {: .info}
>
> Although the folding algorithm commonly downcases characters, folding is not a general purpose downcasing process. It exists only to facilitate case insensitive string comparison.


```elixir
iex> Unicode.String.equals_ignoring_case? "ABC", "abc"
true

iex> Unicode.String.equals_ignoring_case? "beißen", "beissen"
true

iex> Unicode.String.equals_ignoring_case? "grüßen", "grussen"
false
```

### Case Mapping

The [Unicode Case Mapping](https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf) algorithm defines the process and data to transform text into upper case, lower case or title case. Since most languages are not bicameral, characters which have no case mapping remain unchanged.

Three case mapping functions are provided:

* `Unicode.String.upcase/2` which will convert text to upper case characters.
* `Unicode.String.downcase/2` which will convert text to lower case characters.
* `Unicode.String.titlecase/2` which will convert text to title case.  Title case means that the first character or each word is set to upper case and all other characters in the word are set to lower case. `Unicode.String.split/2` is used to split the string into words before title casing.

Each function operates in a locale-aware manner implementing some basic capabilities:

* Casing rules for the Turkish dotted capital `I` and dotless small `i`.
* Casing rules for the retention of dots over `i` for Lithuanian letters with additional accents.
* Titlecasing of IJ at the start of words in Dutch.
* Removal of diacritics when upper casing letters in Greek.

There are other casing rules that are not currently implemented such as:

* Titlecasing of second or subsequent letters in words in orthographies that include caseless letters such as apostrophes.
* Uppercasing of U+00DF `ß` latin small letter sharp `s` to U+1E9E `ẞ` latin capital letter sharp `s`.

```elixir
# Basic case transformation
iex> Unicode.String.upcase("the quick brown fox")
"THE QUICK BROWN FOX"

# Dotted-I in Turkish and Azeri
iex> Unicode.String.upcase("Diyarbakır", locale: :tr)
"DİYARBAKIR"

# Upper case in Greek removes diacritics
iex> Unicode.String.upcase("Πατάτα, Αέρας, Μυστήριο", locale: :el)
"ΠΑΤΑΤΑ, ΑΕΡΑΣ, ΜΥΣΤΗΡΙΟ"

# Lower case Greek with a final sigma
iex> Unicode.String.downcase("ὈΔΥΣΣΕΎΣ", locale: :el)
"ὀδυσσεύς"

# Title case Dutch with leading dipthong
iex> Unicode.String.titlecase("ijsselmeer", locale: :nl)
"IJsselmeer"
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
# they do not cause a break)
iex> Unicode.String.split "No, I don't have a Ph.D. but I don't think it matters.", break: :word, trim: true
["No", ",", "I", "don't", "have", "a", "Ph.D", ".", "but", "I", "don't",
 "think", "it", "matters", "."]

iex> Unicode.String.split "No, I don't have a Ph.D. but I don't think it matters.", break: :sentence, trim: true
["No, I don't have a Ph.D. but I don't think it matters."]

# Sentence Break suppressions are locale sensitive.
iex> Unicode.String.Segment.known_locales
["de", "el", "en", "en-US", "en-US-POSIX", "es", "fi", "fr", "it", "ja", "pt",
 "root", "ru", "sv", "zh", "zh-Hant"]

iex> Unicode.String.split "Non, c'est M. Dubois.", break: :sentence, trim: true, locale: "fr"
["Non, c'est M. Dubois."]

# Note that break: :line does NOT mean split the string
# at newlines. It splits the string where a line break would be
# acceptable. This is very useful for calculating where
# to perform word-wrap on some text.
iex> Unicode.String.split "This is a sentence. And another.", break: :line
["This ", "is ", "a ", "sentence. ", "And ", "another."]
```

### Dictionary-based word segmentation

Some languages, commonly east asian languages, don't typically use whitespace to separate words so a dictionary lookup is more appropriate - although not perfect.

This implementation supports dictionary-based word breaking for:

* Chinese (`zh`, `zh-Hant`, `zh-Hans`, `zh-Hant-HK`, `yue`, `yue-Hans`) locales,
* Japanese (`ja`) using the same dictionary as for Chinese,
* Thai (`th`),
* Lao (`lo`),
* Khmer (`km`) and
* Burmese (`my`).

The dictionaries implemented are those used in the [CLDR](https://cldr.unicode.org) since they are under an open source license and also for consistency with [ICU](https://icu.unicode.org).

Note that these dictionaries need to be downloaded with `mix unicode.string.download.dictionaries` prior to use. Each dictionary will be parsed and loaded into [persistent_term](https://www.erlang.org/doc/man/persistent_term) on demand. Note that each dictionary has a sizable memory footprint as measured by `:persistent_term.info/0`:

| Dictionary  | Memory Mb   |
| ----------- | ----------: |
| Chinese     | 104.8       |
| Thai        | 9.6         |
| Lao         | 11.4        |
| Khmer       | 38.8        |
| Burmese     | 23.1        |

## Segment Streaming

Segmentation can also be streamed using `Unicode.String.stream/2`. For large strings this may improve memory usage since the intermediate segments will be garbage collected when they fall out of scope.

```elixir
iex> Enum.to_list Unicode.String.stream("this is a list of words", trim: true)                       ["this", "is", "a", "list", "of", "words"]

iex> Enum.map Unicode.String.stream("this is a list of words", trim: true),
...>   fn word -> %{word: word, length: String.length(word)} end
[
  %{length: 4, word: "this"},
  %{length: 2, word: "is"},
  %{length: 1, word: "a"},
  %{length: 3, word: "list"},
  %{length: 2, word: "of"},
  %{length: 5, word: "words"}
]
```

## References

* Unicode maintains a [break testing utility](https://util.unicode.org/UnicodeJsps/breaks.jsp).

