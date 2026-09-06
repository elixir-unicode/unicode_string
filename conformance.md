# UAX #29 Conformance and ICU Comparison

This document describes how `unicode_string` conforms to the Unicode segmentation standards and where it differs from the ICU reference implementation.

## Standards Implemented

| Standard | Scope | Status |
|----------|-------|--------|
| [UAX #29](https://unicode.org/reports/tr29/) | Grapheme cluster, word, and sentence segmentation | Implemented via CLDR rules |
| [UAX #14](https://unicode.org/reports/tr14/) | Line break opportunities | Implemented via CLDR rules |

All four break types defined by CLDR are supported: grapheme cluster break, word break, sentence break, and line break.

## Rule Source

Each break type is implemented as a single-pass walker over the string. Every position is decided from the character at that position plus a small amount of state carried forward from the characters already seen, so the cost is proportional to the length of the input rather than to the number of rules. Earlier releases evaluated a pair of PCRE regular expressions per rule per position; that engine was replaced in version 2.1.0.

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

Erlang's `string` module (which underlies Elixir's `String.first/1` and `String.graphemes/1`) implements an older grapheme cluster algorithm that does not include rule GB9c (Indic conjunct break). This means Erlang treats a virama as a combining mark that joins with both the preceding and following consonants into a single cluster, while UAX #29 breaks the cluster at the conjunct boundary.

Example with Kannada `ಕ್ಯಾಥಿ` (KA + VIRAMA + YA + AA-vowel + THA + I-vowel):

| Algorithm | First cluster | Second cluster | Third cluster |
|-----------|--------------|----------------|---------------|
| Erlang/OTP | ಕ್ಯಾ (4 codepoints) | ಥಿ (2 codepoints) | — |
| UAX #29 / `unicode_string` | ಕ್ (2 codepoints) | ಯಾ (2 codepoints) | ಥಿ (2 codepoints) |

This distinction matters for any operation that extracts the "first letter" of a word in a Brahmic script (Devanagari, Bengali, Tamil, Telugu, Kannada, Malayalam, Sinhala, Khmer, Myanmar, Thai, Lao, Tibetan, etc.).

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

The only part of the standard not implemented is locale tailoring; see *Differences from ICU* below.

### Test coverage

19,309 of 19,346 line break test cases from the Unicode test data file pass (99.81%), and 176 of 240 line break cases from ICU's `rbbitst.txt`. The remaining failures are dominated by the CJK locale tailorings.

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

## Differences from ICU

### Same approach

* Rule definitions from CLDR XML (same source data as ICU).
* Extended grapheme clusters with Indic conjunct break support (rule GB9c).
* Dictionary-based word breaking for CJK and Southeast Asian scripts using the same CLDR dictionaries.
* 3-word lookahead algorithm for Southeast Asian dictionary break matching ICU's `DictionaryBreakEngine`.
* Abbreviation suppression for sentence breaks using locale-specific lists.
* CLDR `$MidLetter` modification for word breaks (excluding colons).

### Different approach

* **Rule engine.** ICU compiles rules into a state machine (RBBI — Rule-Based Break Iterator) driven by generated transition tables. `unicode_string` hand-transcribes the rules into an ordered decision function over a small carried state. Both are single-pass and both cost O(1) per character; ICU's table dispatch is considerably cheaper per step, as the benchmark below shows.

* **CJK dictionary integration.** ICU integrates dictionary lookup directly into the RBBI state machine, triggering dictionary segmentation when the state machine enters an ideographic span. `unicode_string` uses a greedy dictionary match within the standard `split` path for CJK locales.

* **Southeast Asian dictionary integration.** ICU's `DictionaryBreakEngine` is invoked by the RBBI state machine when it encounters a dictionary-script span. `unicode_string` partitions the input text by script range first, then applies the dictionary algorithm to target-script spans and the rule-based algorithm to everything else.

* **Performance characteristics.** See *Performance* below.

* **Locale resolution.** ICU uses its own locale resolution with resource bundle fallback. `unicode_string` accepts atoms, strings, and `Localize.LanguageTag` structs, with explicit ancestor locale merging for segmentation rules.

## Performance

`benchee/icu_compare.exs` measures this library against ICU4C's break iterator through a small
NIF (`benchee/icu/`). Build it with `benchee/icu/build.sh`, then run
`mix run benchee/icu_compare.exs`.

The comparison is set up to be unfavourable to this library rather than flattering:

* ICU's UTF-8 to UTF-16 conversion and iterator construction happen once, before timing, and
  each timed call runs 25 complete passes inside C, so the NIF boundary crossing is amortised
  away rather than being charged to ICU.
* Every dictionary is loaded during warmup, so no timed native run pays for a `File.read` or a
  trie build.
* The ICU figure quoted is the one that also converts each segment back to UTF-8, which is
  closer to what `Unicode.String.split/2` does than walking boundaries alone. The native side
  still additionally allocates an Erlang binary per segment, which ICU never does.

Per segmentation pass, on Elixir 1.20.2 / OTP 29 / Apple silicon:

| Corpus | Break | Bytes | ICU | `unicode_string` | Ratio |
|--------|-------|------:|----:|-----------------:|------:|
| English prose | word | 1,800 | 40 µs | 3.01 ms | 75× |
| English prose | line | 1,800 | 29 µs | 4.49 ms | 155× |
| English prose | grapheme | 1,800 | 71 µs | 3.62 ms | 51× |
| English prose | sentence | 1,800 | 2 µs | 1.62 ms | 753× |
| Japanese | word | 2,400 | 169 µs | 1.94 ms | 11× |
| Thai | word | 2,200 | 58 µs | 3.89 ms | 67× |
| Mixed script | word | 1,640 | 123 µs | 2.47 ms | 20× |

ICU is between one and three orders of magnitude faster. That is the expected shape of the
result — ICU is optimised C dispatching through generated tables, against BEAM code walking a
string codepoint by codepoint — but two things in the table are worth noting.

The dictionary-driven cases are the *closest*, not the furthest apart: Japanese word breaking
is only 11× slower, because both implementations spend most of their time in trie lookups
rather than in rule dispatch.

Sentence breaking is the outlier at 753×, far worse than the other break types, which suggests
something pathological rather than a general dispatch cost. It has not been investigated.

## Unicode Version

Rules and property data correspond to Unicode 18.0. Note that Unicode 18 changed rule GB9c: a linker no longer requires a preceding `Indic_Conjunct_Break=Consonant`, so a conjunct sequence can open from any position including the start of text. The draft UAX #29 prose had not been updated to reflect this at the time of writing, though `GraphemeBreakTest-18.0.0.txt` had.
