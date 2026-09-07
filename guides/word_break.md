# Word Break

Word segmentation divides text into words and the things between them. It is the default break type, and it is what you want for word counts, search indexing, and "select word" behaviour.

```elixir
iex> Unicode.String.split("This is a sentence.", break: :word)
["This", " ", "is", " ", "a", " ", "sentence", "."]
```

The segments cover the whole input, including spaces and punctuation. `trim: true` drops the segments that are entirely whitespace:

```elixir
iex> Unicode.String.split("This is a sentence.", break: :word, trim: true)
["This", "is", "a", "sentence", "."]
```

Punctuation is still there. To keep only the word-like segments, filter with `Unicode.String.word_like?/1`:

```elixir
iex> "This is a sentence." |> Unicode.String.split(break: :word, trim: true) |> Enum.filter(&Unicode.String.word_like?/1)
["This", "is", "a", "sentence"]
```

## What counts as one word

[UAX #29](https://unicode.org/reports/tr29/) keeps together several things that a naive split on spaces would separate. Contractions stay whole because an apostrophe between letters does not break:

```elixir
iex> Unicode.String.split("don't", break: :word)
["don't"]
```

Numbers keep their internal separators:

```elixir
iex> Unicode.String.split("1,234.56", break: :word)
["1,234.56"]
```

And a full stop inside an abbreviation does not split it from the letters around it in the way a sentence-ending full stop would.

## CLDR deviations

CLDR tailors the Unicode rules slightly, and this library follows CLDR. The most visible change is that a colon is not treated as a mid-letter character, so `a:b` breaks where the plain Unicode rules would keep it together. This is why a handful of lines in the Unicode conformance file are excluded from the test suite — they test the untailored behaviour that CLDR deliberately changes.

## Scripts without spaces

Thai, Lao, Khmer, Burmese, Chinese and Japanese do not put spaces between words, so no rule over character classes can find the boundaries. These need a dictionary, and the dictionaries are downloaded separately:

```bash
mix unicode.string.download.dictionaries
```

With a dictionary present, pass the locale:

```elixir
Unicode.String.split("ทดสอบภาษาไทย", break: :word, locale: :th)
```

Without one, the standard rules are used instead, which is a much better answer than shattering the text into single characters. The locales with dictionaries are returned by `Unicode.String.Dictionary.known_dictionary_locales/0`.

Mixed-script text is handled by partitioning first: runs of the dictionary's own script go to the dictionary and everything else goes to the rules. Handing a whole mixed string to a dictionary that knows only one script would break the rest into single characters.

## Streaming

For large inputs, `stream/2` produces segments lazily:

```elixir
iex> "one two three" |> Unicode.String.stream(break: :word, trim: true) |> Enum.to_list()
["one", "two", "three"]
```
