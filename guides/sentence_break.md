# Sentence Break

Sentence segmentation divides text at sentence boundaries. The hard part is not finding full stops — it is deciding which full stops actually end a sentence.

```elixir
iex> Unicode.String.split("Hello there. Goodbye.", break: :sentence)
["Hello there. ", "Goodbye."]
```

Note that the trailing space belongs to the sentence it follows. `trim: true` removes segments that are entirely whitespace, but it does not strip the whitespace from within a segment; use `String.trim/1` for that.

## Abbreviations

A full stop after "Mr" or "Ph.D" does not end a sentence. There is no rule over character classes that can tell the difference, so CLDR ships a list of abbreviations per locale, and this library applies them as a post-pass: the rules decide there is a break, and the suppression list cancels it.

```elixir
iex> Unicode.String.split("No, I don't have a Ph.D. but I don't think it matters.", break: :sentence)
["No, I don't have a Ph.D. but I don't think it matters."]
```

Suppressions are locale-specific, and they are on by default. Turn them off with `suppressions: false`:

```elixir
iex> Unicode.String.split("Hello Mr. Smith.", break: :sentence, suppressions: false)
["Hello Mr. ", "Smith."]
```

The list for a locale is available directly:

```elixir
iex> suppressions = Unicode.String.Segment.suppressions!(:en, :sentence_break)
iex> "Alt." in suppressions
true
```

German has a considerably longer list than English — 241 entries against 151 — which matters for text with many abbreviations. It is worth seeing the mechanism bite. A sentence ending in an ordinary noun breaks:

```elixir
iex> Unicode.String.split("Das ist ein Haus. Und noch eins.", break: :sentence, locale: :de)
["Das ist ein Haus. ", "Und noch eins."]
```

But `Test.` happens to be in CLDR's German list, so an otherwise identical sentence does not:

```elixir
iex> Unicode.String.split("Das ist ein Test. Und noch einer.", break: :sentence, locale: :de)
["Das ist ein Test. Und noch einer."]
```

That is the list working as designed rather than a defect — but it shows that a suppression list is a blunt instrument, and that turning it off is sometimes the right call for a given corpus.

## Locale tailoring

Greek adds U+003B SEMICOLON and U+037E GREEK QUESTION MARK to the set of sentence terminators, so Greek text breaks at the erotimatiko where other locales do not:

```elixir
iex> Unicode.String.split("γδ; Ε ζη. Θι", break: :sentence, locale: :el)
["γδ; ", "Ε ζη. ", "Θι"]

iex> Unicode.String.split("γδ; Ε ζη. Θι", break: :sentence, locale: :en)
["γδ; Ε ζη. ", "Θι"]
```

This is the only sentence break class tailoring CLDR currently defines.

## Lookahead

Rule SB8 of [UAX #29](https://unicode.org/reports/tr29/) has unbounded forward lookahead: after a full stop, the algorithm scans ahead for the next letter, and if it is lower case the sentence has not ended. This is what keeps "e.g. this" together, and it is why an ambiguous full stop can require reading a long way forward before it can be resolved.

## Streaming

Sentence segmentation is a natural fit for streaming, since a large document produces relatively few, relatively large segments:

```elixir
iex> "One. Two. Three." |> Unicode.String.stream(break: :sentence) |> Enum.take(2)
["One. ", "Two. "]
```
