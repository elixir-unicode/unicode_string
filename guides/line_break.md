# Line Break

Line breaking finds the positions where a line of text *may* be wrapped. It does not find newline characters, and it does not decide where to wrap — that depends on how wide your line is. It tells you where wrapping is permitted.

```elixir
iex> Unicode.String.split("This is a sentence.", break: :line)
["This ", "is ", "a ", "sentence."]
```

Each segment carries the whitespace that follows it, because a break opportunity sits *after* a space, not before it. Joining the segments always reproduces the input.

## Wrapping text

The segments are the units you assemble into lines. Accumulate them until adding the next one would exceed your width, then start a new line:

```elixir
iex> "the quick brown fox jumps"
...> |> Unicode.String.split(break: :line)
...> |> Enum.reduce([""], fn segment, [line | done] ->
...>   if String.length(line) + String.length(segment) > 12 do
...>     [segment, line | done]
...>   else
...>     [line <> segment | done]
...>   end
...> end)
...> |> Enum.reverse()
...> |> Enum.map(&String.trim_trailing/1)
["the quick", "brown fox", "jumps"]
```

Measuring with `String.length/1` assumes every character occupies one column, which is wrong for East Asian text and for combining marks. Use a width-aware measure if that matters to you.

## What holds text together

[UAX #14](https://unicode.org/reports/tr14/) is the largest of the four algorithms, with around thirty rules. Most of them exist to stop a break in a place that would look wrong.

Punctuation binds to what it belongs to. There is no break after an opening bracket, and none before a closing one:

```elixir
iex> Unicode.String.split("a (b) c", break: :line)
["a ", "(b) ", "c"]
```

Numbers hold together with their prefixes, suffixes and internal punctuation:

```elixir
iex> Unicode.String.split("$1,234.56 total", break: :line)
["$1,234.56 ", "total"]
```

A hyphen permits a break after it, which is how hyphenated words wrap:

```elixir
iex> Unicode.String.split("co-operate now", break: :line)
["co-", "operate ", "now"]
```

## East Asian text

CJK text has break opportunities almost everywhere, since there are no spaces. The rules still prevent breaks in front of small kana, closing punctuation and the like.

Japanese and Chinese tailor the rules: `ja`, `zh` and `zh-Hant` treat conditional Japanese starters — small kana and similar — as ideographs rather than non-starters, which permits a break before them. This is the tailoring usually called CJK *loose* line breaking.

```elixir
iex> Unicode.String.split("あぁx", break: :line, locale: :root)
["あぁ", "x"]

iex> Unicode.String.split("あぁx", break: :line, locale: :ja)
["あ", "ぁ", "x"]
```

The CSS line break modes — `strict`, `normal` and `loose` — are not implemented.

## Scripts needing a dictionary

Thai, Lao, Khmer and Burmese need a dictionary to find line break opportunities, for the same reason they need one for word breaking: the rules alone cannot see word boundaries in a script without spaces. The dictionary pass runs automatically when the text contains those scripts and a dictionary is available.

It only ever adds breaks between two characters of the dictionary's own script, so the punctuation rules above continue to hold at the edges of a dictionary run:

```elixir
iex> Unicode.String.split("(ทิวเขาแดนลาว)", break: :line)
["(ทิว", "เขา", "แดน", "ลาว)"]
```

Text containing no dictionary script skips the pass entirely, at the cost of a single scan for two UTF-8 lead bytes.

## Testing a single position

If you are implementing your own layout loop, `break?/2` answers whether a break is permitted at one position without segmenting the whole string:

```elixir
iex> Unicode.String.break?({"a ", "b"}, break: :line)
true

iex> Unicode.String.break?({"(", "a"}, break: :line)
false
```
