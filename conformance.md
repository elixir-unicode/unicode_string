# UAX #29 Conformance and ICU Comparison

This document describes how `unicode_string` conforms to the Unicode segmentation standards and where it differs from the ICU reference implementation.

## Standards Implemented

| Standard | Scope | Status |
|----------|-------|--------|
| [UAX #29](https://unicode.org/reports/tr29/) | Grapheme cluster, word, and sentence segmentation | Implemented via CLDR rules |
| [UAX #14](https://unicode.org/reports/tr14/) | Line break opportunities | Implemented via CLDR rules |

All four break types defined by CLDR are supported: grapheme cluster break, word break, sentence break, and line break.

## Rule Source

Each break type is implemented as a *table-driven engine* generated at compile time from the state machine tables published in [PRI #555](https://www.unicode.org/review/pri555/). A symbol table resolves each character to a symbol, and a transition table drives a deterministic automaton across the string in one pass; no rule of the annex appears as code. Adopting a new Unicode version is a data update rather than a re-reading of the rules.

Two earlier engines remain in the tree. A *direct-coded rule engine* under `Unicode.String.Break` compiles the rules of each annex into ordered guards and function clauses; it is no longer on the dispatch path but is retained as an independent cross-check, since two implementations disagreeing is how transcription defects get found. Before that, releases up to 2.1.0 evaluated a pair of PCRE regular expressions per rule per position.

Locale-specific data — sentence break suppressions in particular — is still read from the [CLDR](https://cldr.unicode.org) XML segment rule definitions shipped in `priv/segments/`.

CLDR rules are a superset of the Unicode rules defined in UAX #29. Where CLDR modifies or extends the Unicode definitions, those changes are documented below.

## Grapheme Cluster Break

Implements **extended grapheme clusters** as defined in [UAX #29 Section 3.1](https://www.unicode.org/reports/tr29/#Grapheme_Cluster_Boundaries). This is the modern definition that includes:

* Hangul syllable sequences (rules GB6–GB8).
* Extend and ZWJ attachment (rule GB9).
* SpacingMark attachment (rule GB9a).
* Prepend characters (rule GB9b).
* Indic conjunct sequences via `Indic_Conjunct_Break` properties (rule GB9c) — this is the rule that correctly segments Brahmic scripts like Kannada, Khmer, and Malayalam at virama/halant boundaries.
* Emoji ZWJ sequences (rule GB11).
* Regional indicator (emoji flag) pairs (rules GB12–GB13).

### Difference from Erlang/OTP grapheme clusters

Erlang's `string` module — which underlies Elixir's `String.first/1` and `String.graphemes/1` — does implement GB9c. The difference is in how the sets that rule operates on are derived.

UAX #29 defines GB9c over the `Indic_Conjunct_Break` property, a derived property curated for this purpose: 23 codepoints have `InCB=Linker`. OTP instead derives its equivalent sets from `IndicSyllabicCategory.txt`, in [`gen_unicode_mod.escript`](https://github.com/erlang/otp/blob/master/lib/stdlib/uc_spec/gen_unicode_mod.escript), which generates the `unicode_util` module at build time:

```erlang
Linkers = maps:get(virama, GBP) ++ maps:get(invisible_stacker, GBP),
Consonants = maps:get(consonant, GBP) ++ maps:get(vowel_independent, GBP) ++ [{16#1B0B, 16#1B0C}],
```

Every Indic virama therefore counts as a linker, producing 41 rather than 23, and independent vowels count as consonants, so OTP's sets are strict supersets of the property's — 1,943 extra consonants as well as 21 extra linkers. (OTP 29 reports `unicode_util:spec_version()` of `{17,0}`, where the property defines 20 linkers rather than 18.0's 23; the derivation is the same either way.) The consequence is that OTP joins conjuncts in scripts where `Indic_Conjunct_Break` does not. U+0CCD KANNADA SIGN VIRAMA is `InCB=Extend` in the UCD but a linker to OTP, so a Kannada conjunct stays together under `String.graphemes/1` and breaks under UAX #29.

Where the two sets agree the results agree: Devanagari U+0915 U+094D U+0937 is a single cluster under both, because U+094D is `InCB=Linker` and both consonants are `InCB=Consonant`.

Example with Kannada `ಕ್ಯಾಥಿ` (KA + VIRAMA + YA + AA-vowel + THA + I-vowel):

| Algorithm | First cluster | Second cluster | Third cluster |
|-----------|--------------|----------------|---------------|
| Erlang/OTP | ಕ್ಯಾ (4 codepoints) | ಥಿ (2 codepoints) | — |
| UAX #29 / `unicode_string` | ಕ್ (2 codepoints) | ಯಾ (2 codepoints) | ಥಿ (2 codepoints) |

The scripts affected are those whose virama is not `InCB=Linker` — Kannada, Tamil, Gurmukhi and Sinhala among them. Devanagari, Bengali, Gujarati, Oriya, Telugu and Malayalam are unaffected, since their viramas are in both sets. The distinction matters for any operation that extracts the "first letter" of a word in one of the affected scripts.

### Test coverage

All 853 grapheme break test cases from the Unicode test data file pass. They are shipped in `test/support/test_data/grapheme_break_test.txt`.

## Word Break

Implements UAX #29 word break rules as customised by CLDR. The CLDR rules are used rather than the raw Unicode rules because CLDR provides locale-sensitive tailoring and dictionary-based segmentation for scripts that don't use spaces.

### CLDR deviations from Unicode word break rules

CLDR modifies the `$MidLetter` variable to exclude three characters:

```
Unicode:  $MidLetter = \p{Word_Break=MidLetter}
CLDR:     $MidLetter = [\p{Word_Break=MidLetter} - [: \uFE55 \uFF1A]]
```

The excluded characters are COLON (U+003A), SMALL COLON (U+FE55), and FULLWIDTH COLON (U+FF1A). This means that colons do not function as mid-word punctuation in CLDR word breaking. For example, `one:two` breaks into `["one", ":", "two"]` under CLDR rules but would remain `["one:two"]` under pure Unicode rules.

This causes 22 lines in the Unicode word break test data to produce different results. These lines are excluded from the conformance test suite and documented in `test/word_break_test.exs`.

### Dictionary-based word segmentation

For languages that don't use whitespace to separate words, the standard rule-based approach is supplemented with dictionary lookup. Two different strategies are used:

**CJK locales** (`zh`, `zh-Hant`, `zh-Hans`, `zh-Hant-HK`, `yue`, `yue-Hans`, `ja`): Standard UAX #29 word break rules are applied, with dictionary lookups used to segment runs of ideographic characters. This matches ICU's approach of using the word break rules to identify ideographic spans and then applying dictionary segmentation within those spans.

**Southeast Asian locales** (`th`, `lo`, `km`, `my`): A lookahead-based dictionary break algorithm (described below) replaces the standard word break rules for text in the locale's script. Non-script text (e.g., embedded Latin words) falls back to the standard rule-based algorithm.

### Test coverage

All 1,944 word break test lines from the Unicode test data file pass, with 22 CLDR-specific lines excluded. Additional dictionary-based segmentation tests cover Chinese, Japanese, Thai, Lao, Khmer, and Burmese.

## Sentence Break

Implements UAX #29 sentence break rules as customised by CLDR.

### Abbreviation suppression

CLDR adds a sentence break suppression rule (inserted as rule 10.5) that prevents breaks after known abbreviations. Abbreviation lists are locale-specific — for example, English suppressions include "Mr", "Mrs", "Dr", "Jr", "Sr", "vs", "Ph.D", and others. This rule is compiled with the `:caseless` option so that "dr." and "Dr." are both suppressed.

Suppression rules are defined for these locales: `de`, `el`, `en`, `en-US`, `en-US-POSIX`, `es`, `fi`, `fr`, `it`, `ja`, `pt`, `ru`, `sv`, `zh`, `zh-Hant`.

### Test coverage

All 512 sentence break test cases from the Unicode test data file pass.

## Line Break

Implements [UAX #14](https://www.unicode.org/reports/tr14/) (Unicode Line Breaking Algorithm). This determines where line breaks (word-wrap opportunities) are acceptable, not where newline characters appear.

Every rule in the standard is implemented, including those that depend on properties beyond a character's line break class:

| Rule | Additional property required |
|------|------------------------------|
| LB1 | `General_Category`, to resolve `SA` to `CM` or `AL` |
| LB15a, LB15b | `General_Category`, to identify initial (`Pi`) and final (`Pf`) quotation marks |
| LB19a, LB30 | `East_Asian_Width`, to exclude `F`, `W` and `H` |
| LB28a | U+25CC DOTTED CIRCLE, which is `lb=AL` but plays its own role in a Brahmic syllable |
| LB30b | `Extended_Pictographic` and `General_Category=Cn`, which together match characters carrying `lb=ID` or `lb=XX` |

CLDR's locale tailoring of the line break classes is implemented for `ja`, `zh` and `zh-Hant`; see *Locale tailoring* below. The line break *modes* — strict, normal and loose — are not.

### Test coverage

All 19,346 line break test cases from the Unicode test data file pass, and 177 of 240 line break cases from ICU's `rbbitst.txt`.

The ICU corpus is not fully reachable. Its `<locale>` lines carry line break mode attributes — `ja@lb=loose`, `ja@lb=strict`, `ja@lw=phrase` — and several blocks pair the same input with different expected output depending on the mode. Read without those attributes they contradict each other, so no implementation can satisfy them all at once. Of the 63 remaining failures, 42 are `ja` and 11 are `ko`.

## Dictionary Break Algorithm

The dictionary break algorithm is implemented in `Unicode.String.DictionaryBreak` and applies to Thai, Lao, Khmer, and Burmese. It follows the same approach as ICU's `DictionaryBreakEngine`.

### Algorithm

At each position in a run of target-script characters:

1. **Gather candidates.** All dictionary words starting at the current position are found via prefix search against a trie-structured dictionary, producing a list of candidate lengths sorted shortest to longest.

2. **Select best candidate.** If exactly one candidate exists, it is accepted. If multiple candidates exist, a 3-word lookahead selects the candidate that leads to the longest chain of consecutive dictionary words. Candidates are tried longest-first; the first candidate confirmed by a 3-word chain is accepted.

3. **Handle non-dictionary text.** When no dictionary word is found (or only a very short word of fewer than 3 codepoints), the algorithm scans forward until finding a position where dictionary words resume. The non-dictionary stretch is combined with the preceding word.

4. **Absorb combining marks.** After each word boundary, any following Unicode combining marks (General Category M) are absorbed into the preceding word. This keeps vowel signs, tone marks, and virama/coeng characters attached to their base consonant.

5. **Absorb Thai suffixes.** For Thai only, the suffix characters PAIYANNOI (U+0E2F) and MAIYAMOK (U+0E46) are absorbed into the preceding word when no dictionary word follows.

### Mixed-script text

When text contains a mix of the locale's script and other scripts, `split_with_fallback/3` partitions the text into same-script runs. Dictionary breaking is applied to runs in the target script; a fallback function (the standard UAX #29 word breaker) handles the rest.

### Dictionaries

The dictionaries are those shipped with CLDR/ICU, converted to trie structures and stored in `:persistent_term` on first access.

| Dictionary | Source file | Loaded size |
|-----------|-------------|-------------|
| Chinese/Japanese | `chinese_japanese.txt` | ~105 MB |
| Thai | `thai.txt` | ~10 MB |
| Lao | `lao.txt` | ~11 MB |
| Khmer | `khmer.txt` | ~39 MB |
| Burmese | `burmese.txt` | ~23 MB |

Dictionaries must be downloaded before use with `mix unicode.string.download.dictionaries`.

## Locale Tailoring

UAX #14 and UAX #29 define one set of rules for every language. CLDR carries per-locale departures from them in `priv/segments/`, and this library applies the ones below. They are handled by `Unicode.String.Break.Tailoring`, outside the break engines, because a table-driven engine resolves a character to a symbol with a table fixed at compile time and has nowhere to put a per-locale exception.

| Locale | Break | Tailoring |
|---|---|---|
| `el` | Sentence | `$STerm` gains U+003B SEMICOLON and U+037E GREEK QUESTION MARK, so Greek text breaks at the erotimatiko |
| `ja`, `zh`, `zh-Hant` | Line | `Line_Break=Conditional_Japanese_Starter` moves from `$NS` to `$ID`, so small kana break as ideographs rather than as non-starters — CJK *loose* line breaking |
| any | Sentence | Abbreviation suppressions, listed per locale; see *Abbreviation suppression* above |

A class tailoring is applied by rewriting the affected characters to standard characters carrying the class the locale wants, before the machine runs. Each substitute encodes to the same number of UTF-8 bytes as the character it replaces, so every offset the machine reports still indexes the original string and every segment is sliced from the original. The rewrite never reaches the caller.

The rewrite is applied once per call rather than once per segment. Applying it to the remainder at each boundary would make splitting quadratic in the length of the input, which would fall hardest on exactly the locales that have a tailoring.

Three CLDR tailorings are not implemented. `en-US-POSIX` moves `.` from `$MidNumLet` to `$MidNum` for word breaking. `ja` adds word break rules 13.3 and 13.4, holding runs of Hiragana and of Ideographic characters together — Japanese word breaking uses the dictionary breaker instead. The `fi` and `sv` word break entries redefine `$MidLetter` to the same value root already gives it and so are no-ops.

## Differences from ICU

### Same approach

* Rule definitions from CLDR XML (same source data as ICU).
* Extended grapheme clusters with Indic conjunct break support (rule GB9c).
* Dictionary-based word breaking for CJK and Southeast Asian scripts using the same CLDR dictionaries.
* 3-word lookahead algorithm for Southeast Asian dictionary break matching ICU's `DictionaryBreakEngine`.
* Abbreviation suppression for sentence breaks using locale-specific lists.
* CLDR `$MidLetter` modification for word breaks (excluding colons).
* Locale tailoring of break classes for Greek sentences and CJK lines; see *Locale Tailoring* above.

### Different approach

* **Rule engine.** Both are now table-driven state machines, which was not true before this release. ICU compiles the CLDR rules itself into transition tables at build time (RBBI — Rule-Based Break Iterator); `unicode_string` compiles in the tables published in PRI #555, which are generated from the same rules but by the Unicode Consortium rather than by either implementation. Both are single-pass and cost O(1) per character. ICU remains considerably faster per step, as the benchmark below shows, but the difference is now one of implementation language and tuning rather than of algorithm.

* **CJK dictionary integration.** ICU integrates dictionary lookup directly into the RBBI state machine, triggering dictionary segmentation when the state machine enters an ideographic span. `unicode_string` uses a greedy dictionary match within the standard `split` path for CJK locales.

* **Southeast Asian dictionary integration.** ICU's `DictionaryBreakEngine` is invoked by the RBBI state machine when it encounters a dictionary-script span. `unicode_string` partitions the input text by script range first, then applies the dictionary algorithm to target-script spans and the rule-based algorithm to everything else.

* **Performance characteristics.** See *Performance* below.

* **Locale resolution.** ICU uses its own locale resolution with resource bundle fallback. `unicode_string` accepts atoms, strings, and `Localize.LanguageTag` structs, with explicit ancestor locale merging for segmentation rules.

## Performance

`benchee/nif_compare.exs` measures this library against ICU4C's break iterator, using the optional NIF described under *The optional ICU backend* below. Build and run it with:

    UNICODE_STRING_NIF=true mix compile
    UNICODE_STRING_NIF=true mix run benchee/nif_compare.exs

The ICU column here is deliberately the most favourable one it could be given:

* ICU's UTF-8 to UTF-16 conversion and iterator construction happen once, before timing, and each timed call runs 25 complete passes inside C, so the NIF boundary crossing is amortised away rather than being charged to ICU.
* Every dictionary is loaded during warmup, so no timed native run pays for a `File.read` or a trie build.
* ICU still converts each segment back to UTF-8, which is closer to what `Unicode.String.split/2` does than walking boundaries alone. The native side additionally allocates an Erlang binary per segment, which ICU never does here.

A third column showing what the NIF costs a real caller — boundary included — is in *The optional ICU backend*.

Per segmentation pass, on Elixir 1.20.2 / OTP 29 / Apple silicon:

| Corpus | Break | Bytes | ICU | `unicode_string` | Ratio |
|--------|-------|------:|----:|-----------------:|------:|
| English prose | word | 1,800 | 41 µs | 1.04 ms | 26× |
| English prose | line | 1,800 | 28 µs | 3.11 ms | 110× |
| English prose | grapheme | 1,800 | 72 µs | 0.85 ms | 12× |
| English prose | sentence | 1,800 | 11 µs | 0.76 ms | 67× |
| Japanese | word | 2,400 | 174 µs | 2.07 ms | 12× |
| Thai | word | 2,200 | 59 µs | 3.84 ms | 65× |
| Mixed script | word | 1,640 | 125 µs | 1.70 ms | 14× |

Line breaking is the outlier now, and it is the one break type with no byte-level fast path: its rules depend on East Asian width, General_Category and lookahead in ways a raw-byte test cannot settle. Grapheme and word breaking decide the common Latin cases directly from UTF-8 bytes, which is why they sit closest to ICU.

ICU remains one to two orders of magnitude faster on the rule-driven paths. That is the expected shape of the result — ICU is optimised C dispatching through generated tables, against BEAM code walking a string codepoint by codepoint — and the ratios are consistent across break types once the measurement is set up correctly.

The dictionary-driven cases are the *closest*, not the furthest apart: Japanese word breaking is only 12× slower, because both implementations spend most of their time in trie lookups rather than in rule dispatch. Those are also the cases that benefit least from the Latin-1 fast path, for the same reason: there is little Latin-1 text in them for it to skip lookups on.

### A measurement trap worth recording

An earlier version of this benchmark reused a single `UBreakIterator` across all 25 passes and reported sentence breaking at 753×, far outside the range of every other break type. That figure was wrong. ICU caches recently returned boundaries, and sentence breaking produces few enough boundaries that an entire 1,800-byte text fits in that cache — so passes 2 through 25 were replaying the first pass rather than segmenting. Word and grapheme breaking produce too many boundaries to fit, which is why only the sentence figure was distorted.

Calling `ubrk_setText` at the start of each pass resets the cache and forces the work to happen. It does not re-convert UTF-8, so it adds no marshalling to ICU's side. Doing so raised ICU's sentence figure 5.7× and left every other break type essentially unchanged, putting sentence breaking back in line with the others.

For the record, this library's sentence breaking scales linearly and is its *fastest* break type on the same input — roughly 1.2 ms against 2.5 ms for word breaking on 1,800 bytes.

### The optional ICU backend

`Unicode.String.Nif` exposes ICU's break iterator through an opt-in NIF, selected with `backend: :nif` on `Unicode.String.split/2`. The same benchmark measures three subjects: the native implementation, the NIF as a caller actually invokes it, and ICU with the BEAM boundary excluded. Per segmentation pass:

| Corpus | Break | native | NIF, end to end | ICU, boundary excluded | NIF gain |
|--------|-------|-------:|----------------:|-----------------------:|---------:|
| English prose | word | 1.05 ms | 0.79 ms | 41 µs | 1.3× |
| English prose | line | 3.40 ms | 0.49 ms | 29 µs | 6.9× |
| English prose | grapheme | 0.86 ms | 0.57 ms | 72 µs | 1.5× |
| English prose | sentence | 0.76 ms | 0.40 ms | 12 µs | 1.9× |
| Japanese | word | 2.04 ms | 0.92 ms | 173 µs | 2.2× |
| Thai | word | 3.87 ms | 0.78 ms | 59 µs | 5.0× |

The gap between the last two columns is the cost of the boundary — converting UTF-8 to UTF-16, constructing an iterator, and allocating an Erlang binary per segment — and it is between 5× and 34× depending on how many segments come back. It consumes most of ICU's advantage.

The practical conclusion is that the NIF is worth enabling for **line breaking and the dictionary locales**, where it is 5–7× faster, and close to pointless for word and grapheme breaking, where the byte-level fast paths bring the native implementation to within 1.3–1.5× of it. Sentence breaking sits in between. Since the NIF also brings ICU's own locale tailorings and its own dictionaries, enabling it changes results as well as timings; it is not a drop-in accelerator.

## Unicode Version

Rules and property data correspond to Unicode 18.0. Note that Unicode 18 changed rule GB9c: a linker no longer requires a preceding `Indic_Conjunct_Break=Consonant`, so a conjunct sequence can open from any position including the start of text. The draft UAX #29 prose had not been updated to reflect this at the time of writing, though `GraphemeBreakTest-18.0.0.txt` had.
