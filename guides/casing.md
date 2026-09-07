# Casing

Changing the case of text looks trivial and is not. The mapping between upper and lower case is not one-to-one, it is not reversible, and it depends on language. `unicode_string` implements the full Unicode casing algorithm together with the locale-specific rules that CLDR defines.

```elixir
iex> Unicode.String.upcase("the quick brown fox")
"THE QUICK BROWN FOX"

iex> Unicode.String.downcase("THE QUICK BROWN FOX")
"the quick brown fox"
```

## Where language matters

Five languages have casing rules of their own, returned by `Unicode.String.special_casing_locales/0`:

```elixir
iex> Unicode.String.special_casing_locales()
[:az, :el, :lt, :nl, :tr]
```

**Turkish and Azeri** distinguish dotted and dotless i. Upper casing a dotted `i` produces `İ`, not `I` — getting this wrong is the classic internationalisation bug, and it changes the meaning of words.

```elixir
iex> Unicode.String.upcase("Diyarbakır", locale: :tr)
"DİYARBAKIR"

iex> Unicode.String.upcase("Diyarbakır")
"DIYARBAKIR"
```

**Greek** removes accents when upper casing, which is normal orthographic practice:

```elixir
iex> Unicode.String.upcase("Πατάτα, Αέρας, Μυστήριο", locale: :el)
"ΠΑΤΑΤΑ, ΑΕΡΑΣ, ΜΥΣΤΗΡΙΟ"
```

Greek also has a final sigma, `ς`, used only at the end of a word. Lower casing chooses the right form from position:

```elixir
iex> Unicode.String.downcase("ὈΔΥΣΣΕΎΣ", locale: :el)
"ὀδυσσεύς"
```

Note that the middle sigmas are `σ` and only the last is `ς`.

**Dutch** title cases the digraph `ij` as a unit, capitalising both letters:

```elixir
iex> Unicode.String.titlecase("ijsselmeer", locale: :nl)
"IJsselmeer"
```

## Title case

Title casing capitalises the first character of each word and lower cases the rest. It segments the string on word boundaries itself, so you do not need to split first.

```elixir
iex> Unicode.String.titlecase("the quick brown fox")
"The Quick Brown Fox"
```

Because it works word by word, the Dutch `ij` rule applies wherever a word begins with the digraph, not only at the start of the string:

```elixir
iex> Unicode.String.titlecase("het ijsselmeer", locale: :nl)
"Het IJsselmeer"
```

## Case-insensitive comparison

Comparing strings without regard to case is not the same as lower casing both and comparing. Case *folding* exists for exactly this: it maps text to a form suitable for comparison, which is not necessarily lower case and is not meant to be displayed.

```elixir
iex> Unicode.String.equals_ignoring_case?("ABC", "abc")
true
```

The difference shows up with German ß, which folds to `ss`:

```elixir
iex> Unicode.String.equals_ignoring_case?("beißen", "beissen")
true
```

That is a *full* fold. A simple fold, which preserves string length, would not equate them. The default here is the full fold, which is what you almost always want for comparison.

Folding is not the same as equality under a locale's collation rules. If you need "resume" to match "résumé", you need normalisation and collation, not case folding.

## Choosing a function

* `upcase/2` and `downcase/2` when you are changing text for display.

* `titlecase/2` when you want the first character capitalised.

* `equals_ignoring_case?/3` when you are comparing. Do not lower case both sides and compare with `==`; it gets ß and a number of other cases wrong.
