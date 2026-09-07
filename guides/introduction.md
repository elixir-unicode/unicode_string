# Introduction

`unicode_string` implements the Unicode text segmentation and casing algorithms for Elixir: where a string can be divided into user-perceived characters, words, sentences and line break opportunities, and how it changes case in a way that respects language.

Elixir's own `String` module covers the common cases well. This library exists for the cases it doesn't: segmentation that follows [UAX #29](https://unicode.org/reports/tr29/) and [UAX #14](https://unicode.org/reports/tr14/) exactly, locale tailoring from [CLDR](https://cldr.unicode.org), and dictionary-based segmentation for scripts that do not put spaces between words.

## Installation

```elixir
def deps do
  [
    {:unicode_string, "~> 2.4"}
  ]
end
```

Thai, Lao, Khmer, Burmese, Chinese and Japanese word segmentation needs dictionaries, which are downloaded separately because of their size:

```bash
mix unicode.string.download.dictionaries
```

## The four break types

Every segmentation function takes a `:break` option naming one of four algorithms. They answer different questions and it is worth being clear which one you want.

| Break | Question it answers | Guide |
|---|---|---|
| `:grapheme` | Where does one user-perceived character end and the next begin? | [Grapheme Cluster Break](grapheme_break.md) |
| `:word` | Where are the word boundaries? | [Word Break](word_break.md) |
| `:sentence` | Where does one sentence end and the next begin? | [Sentence Break](sentence_break.md) |
| `:line` | Where may a line be wrapped? | [Line Break](line_break.md) |

The default is `:word`.

```elixir
iex> Unicode.String.split("Hello there. Goodbye.", break: :sentence)
["Hello there. ", "Goodbye."]

iex> Unicode.String.split("Hello there.", break: :word, trim: true)
["Hello", "there", "."]
```

## The four functions

Each break type is available through the same four entry points.

`split/2` returns all the segments:

```elixir
iex> Unicode.String.split("one two", break: :word, trim: true)
["one", "two"]
```

`next/2` returns the first segment and the rest, so you can drive segmentation yourself:

```elixir
iex> Unicode.String.next("one two", break: :word)
{"one", " two"}
```

`stream/2` returns a lazy enumerable, which avoids materialising every segment of a large string at once:

```elixir
iex> "one two three" |> Unicode.String.stream(break: :word, trim: true) |> Enum.take(2)
["one", "two"]
```

`break?/2` answers whether a boundary falls between two strings:

```elixir
iex> Unicode.String.break?({"one", " two"}, break: :word)
true

iex> Unicode.String.break?({"th", "ere"}, break: :word)
false
```

## Locales

Most of the algorithms are locale-independent, but some are not. Sentence breaking uses per-locale abbreviation lists so that "Mr." does not end a sentence; line breaking treats Japanese small kana differently from the default; Greek adds its own sentence terminator.

```elixir
iex> Unicode.String.split("No, I don't have a Ph.D. but I don't think it matters.", break: :sentence, locale: :en)
["No, I don't have a Ph.D. but I don't think it matters."]
```

A locale with no tailoring falls back to `:root`, which carries the untailored rules. The locales that have segmentation data are returned by `Unicode.String.Segment.known_segmentation_locales/0`.

## Casing

Case conversion is locale-sensitive in ways that surprise people — Turkish has a dotted capital I, Greek drops accents when upper casing, Dutch title cases "ij" as a unit. See the [Casing](casing.md) guide.

```elixir
iex> Unicode.String.upcase("the quick brown fox")
"THE QUICK BROWN FOX"
```

## Conformance

The four break types are generated from the state machine tables published in [PRI #555](https://www.unicode.org/review/pri555/) rather than transcribed from the prose of the annexes, and all four pass the full Unicode conformance corpora. See [`conformance.md`](conformance.md) for the detail, including where this library differs from ICU.

## An optional ICU backend

An opt-in NIF binding to ICU4C is available for workloads where segmentation is the bottleneck. It is off by default, needs ICU system libraries, and falls back to the native implementation whenever it is unavailable, so `backend: :nif` is always safe to pass. `conformance.md` has the measurements and the cases where it is worth enabling.
