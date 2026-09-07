# Grapheme Cluster Break

A grapheme cluster is what a reader thinks of as a single character. It is often one codepoint, but frequently is not: a base letter plus a combining accent, an emoji built from several codepoints joined by zero-width joiners, a Hangul syllable, a flag made of two regional indicators.

This is the segmentation you want whenever you are counting characters, truncating text, moving a cursor, or reversing a string — anywhere splitting mid-cluster would corrupt what the user sees.

```elixir
iex> Unicode.String.split("héllo", break: :grapheme) |> length()
5
```

## Why not `String.graphemes/1`

Elixir's `String.graphemes/1` implements the same algorithm and agrees with this library in the overwhelming majority of cases. It is faster, and for most text it is the right choice.

The two disagree on Indic conjuncts. Rule GB9c of [UAX #29](https://unicode.org/reports/tr29/) keeps a consonant-virama-consonant sequence together as one cluster, but only in the scripts the `Indic_Conjunct_Break` property covers. Erlang's `unicode_util`, which underlies `String.graphemes/1`, derives its equivalent sets from `Indic_Syllabic_Category` instead, which is not restricted by script. It therefore joins conjuncts in around twenty scripts where UAX #29 requires a break.

Kannada is one of them:

```elixir
iex> Unicode.String.split("ಕ್ಯಾ", break: :grapheme)
["ಕ್", "ಯಾ"]

iex> String.graphemes("ಕ್ಯಾ")
["ಕ್ಯಾ"]
```

Devanagari, where the property does apply, agrees:

```elixir
iex> Unicode.String.split("क्ष", break: :grapheme)
["क्ष"]

iex> String.graphemes("क्ष")
["क्ष"]
```

The scripts affected are those whose virama is not `InCB=Linker`, including Tamil, Kannada, Gurmukhi and Sinhala. If you are extracting the first letter of a word in one of those scripts, the difference is visible to your users. Otherwise `String.graphemes/1` is fine.

## Emoji

Emoji sequences are the most common reason a grapheme cluster spans many codepoints. A family emoji is several people joined by zero-width joiners, and a skin tone is a modifier attached to the preceding character.

```elixir
iex> Unicode.String.split("👨‍👩‍👧‍👦", break: :grapheme) |> length()
1

iex> String.length("👨‍👩‍👧‍👦")
1
```

Flags are pairs of regional indicators, and the rule counts them in pairs, so an odd trailing indicator stands alone:

```elixir
iex> Unicode.String.split("🇦🇺🇳🇿", break: :grapheme) |> length()
2
```

## Combining marks

A base character and the marks that follow it form one cluster, however many marks there are. Here `e` is followed by U+0301 COMBINING ACUTE ACCENT — two codepoints, one cluster:

```elixir
iex> "e" <> <<0x0301::utf8>> |> Unicode.String.split(break: :grapheme) |> length()
1
```

Normalising with `String.normalize/2` would turn that into the single codepoint U+00E9, but segmentation does not require you to — the decomposed form is one grapheme cluster either way.

## Performance

Grapheme breaking has an ASCII fast path: two printable ASCII bytes in a row are always a boundary, which is decided without decoding a codepoint or consulting a property table. Text that is mostly Latin costs very little.

If you are segmenting a very large string and only need part of it, `stream/2` avoids building the whole list:

```elixir
iex> "abcdef" |> Unicode.String.stream(break: :grapheme) |> Enum.take(3)
["a", "b", "c"]
```
