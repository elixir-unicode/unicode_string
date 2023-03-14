# Unicode String

Adds functions supporting some string algorithms in the Unicode standard:

* The [Unicode Case Folding](https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf) algorithm to provide case-independent equality checking irrespective of language or script with `Unicode.String.fold/2` and `Unicode.String.equals_ignoring_case?/2`

* The [Unicode Segmentation](https://unicode.org/reports/tr29/) algorithm to detect, break, split or stream strings into grapheme clusters, words, sentences and line break point. See
  * `Unicode.String.split/2`
  * `Unicode.String.break?/2`
  * `Unicode.String.break/2`
  * `Unicode.String.splitter/2`
  * `Unicode.String.next/2`
  * `Unicode.String.stream/2`

* The [Unicode Line Breaking](https://www.unicode.org/reports/tr14/) algorithm to determine line breaks (as in breaks where word-wrapping would be acceptable).

## Examples

### Casing

		iex> Unicode.String.equals_ignoring_case? "ABC", "abc"
		true

		iex> Unicode.String.equals_ignoring_case? "beißen", "beissen"
		true

		iex> Unicode.String.equals_ignoring_case? "grüßen", "grussen"
		false

### Splitting

### Streaming

## Installation

The package can be installed by adding `:unicode_string` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:unicode_string, "~> 1.0"}
  ]
end
```

