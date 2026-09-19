# Grapheme Cluster Break

A grapheme cluster is what a reader thinks of as a single character. It is often one codepoint, but frequently is not: a base letter plus a combining accent, an emoji built from several codepoints joined by zero-width joiners, a Hangul syllable, a flag made of two regional indicators.

This is the segmentation you want whenever you are counting characters, truncating text, moving a cursor, or reversing a string — anywhere splitting mid-cluster would corrupt what the user sees.

```elixir
iex> Unicode.String.split("héllo", break: :grapheme) |> length()
5
```

## Why not `String.graphemes/1`

Elixir's `String.graphemes/1` implements the same algorithm and agrees with this library in the overwhelming majority of cases. It is faster, and for most text it is the right choice. Like `String.length/1` and the other grapheme-based `String` functions it is Erlang's `unicode_util` underneath, so the differences below depend on your OTP release rather than your Elixir version.

The largest difference is in Indic conjuncts. Rule GB9c of [UAX #29](https://unicode.org/reports/tr29/) keeps a consonant-virama-consonant sequence together as one cluster, but only in the scripts the `Indic_Conjunct_Break` property covers. OTP has implemented GB9c since OTP 28, but it derives the sets the rule works on from `Indic_Syllabic_Category` instead, which is not restricted by script. It therefore joins conjuncts in around twenty scripts where UAX #29 requires a break.

Kannada is one of them:

```elixir
iex> Unicode.String.split("ಕ್ಯಾ", break: :grapheme)
["ಕ್", "ಯಾ"]

# On OTP 28 and later, String.graphemes("ಕ್ಯಾ") returns the single
# cluster ["ಕ್ಯಾ"] instead. OTP 27 and earlier agree with this library.
```

Devanagari, where the property does apply, agrees on OTP 28 and later:

```elixir
iex> Unicode.String.split("क्ष", break: :grapheme)
["क्ष"]

# String.graphemes("क्ष") also returns ["क्ष"] on OTP 28 and later.
# OTP 27 and earlier predate GB9c and return ["क्", "ष"].
```

The scripts affected are those whose virama is not `InCB=Linker`, including Tamil, Kannada, Gurmukhi and Sinhala. If you are counting characters or extracting the first letter of a word in one of those scripts, the difference is visible to your users.

OTP also departs from UAX #29 in three narrower cases, which can arise in any script:

* A zero-width non-joiner after a virama asks for the virama to be shown instead of a conjunct, so UAX #29 breaks after it. On OTP 28 and later `String.graphemes/1` keeps the conjunct together across it.

* A combining mark or skin tone modifier after an emoji and a zero-width joiner still belongs to the cluster, but `String.graphemes/1` starts a new one.

* A spacing mark between an emoji and a zero-width joiner ends the emoji sequence, so the next emoji starts a new cluster, but `String.graphemes/1` joins it to the previous one.

```elixir
iex> Unicode.String.split("क्\u200Cष", break: :grapheme)
["क्\u200C", "ष"]

iex> Unicode.String.split("👍\u200D🏽", break: :grapheme)
["👍\u200D🏽"]

# On OTP 28 and later String.graphemes/1 returns ["क्\u200Cष"] for the
# first. Every OTP release returns ["👍\u200D", "🏽"] for the second.
```

The two can also differ because of the Unicode version. This library implements Unicode 18.0, while `String.graphemes/1` follows the version bundled with your OTP release, which is 17.0 in OTP 29. Unicode 18.0 revised GB9c so that a virama joins the following consonant even when no consonant precedes it, and added new characters.

Outside these cases `String.graphemes/1` is fine.

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
