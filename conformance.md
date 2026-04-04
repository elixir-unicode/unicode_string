# UAX #29 Conformance and ICU Comparison

This document describes how `unicode_string` conforms to the Unicode segmentation standards and where it differs from the ICU reference implementation.

## Standards Implemented

| Standard | Scope | Status |
|----------|-------|--------|
| [UAX #29](https://unicode.org/reports/tr29/) | Grapheme cluster, word, and sentence segmentation | Implemented via CLDR rules |
| [UAX #14](https://unicode.org/reports/tr14/) | Line break opportunities | Implemented via CLDR rules |

All four break types defined by CLDR are supported: grapheme cluster break, word break, sentence break, and line break.

## Rule Source

Segmentation rules are not hard-coded. They are read from the [CLDR](https://cldr.unicode.org) XML segment rule definitions shipped in `priv/segments/`. The root rules (`root.xml`) define the default Unicode segmentation behaviour. Locale-specific overrides (e.g., `en.xml`, `fr.xml`, `de.xml`, `ja.xml`) tailor sentence break suppressions and other locale-sensitive rules. At compile time, the XML rules are parsed, variables are expanded, and each rule is compiled to a pair of PCRE regular expressions (left-context and right-context). At runtime, rules are evaluated in sequence order at each candidate break position.

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

796 grapheme break test cases from the Unicode test data file are shipped in `test/support/test_data/grapheme_break_test.txt`.

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

1,974 word break test lines from the Unicode test data file, with 22 CLDR-specific lines excluded. Additional dictionary-based segmentation tests cover Chinese, Japanese, Thai, Lao, Khmer, and Burmese.

## Sentence Break

Implements UAX #29 sentence break rules as customised by CLDR.

### Abbreviation suppression

CLDR adds a sentence break suppression rule (inserted as rule 10.5) that prevents breaks after known abbreviations. Abbreviation lists are locale-specific — for example, English suppressions include "Mr", "Mrs", "Dr", "Jr", "Sr", "vs", "Ph.D", and others. This rule is compiled with the `:caseless` option so that "dr." and "Dr." are both suppressed.

Suppression rules are defined for these locales: `de`, `el`, `en`, `en-US`, `en-US-POSIX`, `es`, `fi`, `fr`, `it`, `ja`, `pt`, `ru`, `sv`, `zh`, `zh-Hant`.

### Test coverage

542 sentence break test cases from the Unicode test data file.

## Line Break

Implements [UAX #14](https://www.unicode.org/reports/tr14/) (Unicode Line Breaking Algorithm) via CLDR rules. This determines where line breaks (word-wrap opportunities) are acceptable, not where newline characters appear.

### Test coverage

19,368 line break test cases from the Unicode test data file.

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

* **Rule engine.** ICU compiles rules into a state machine (RBBI — Rule-Based Break Iterator). `unicode_string` compiles each rule into a pair of PCRE regular expressions and evaluates them sequentially at each break position. The ICU approach is faster for large texts; the regex approach is simpler to implement and debug.

* **CJK dictionary integration.** ICU integrates dictionary lookup directly into the RBBI state machine, triggering dictionary segmentation when the state machine enters an ideographic span. `unicode_string` uses a greedy dictionary match within the standard `split` path for CJK locales.

* **Southeast Asian dictionary integration.** ICU's `DictionaryBreakEngine` is invoked by the RBBI state machine when it encounters a dictionary-script span. `unicode_string` partitions the input text by script range first, then applies the dictionary algorithm to target-script spans and the rule-based algorithm to everything else.

* **Performance characteristics.** ICU's state machine evaluates a constant number of table lookups per character. `unicode_string` evaluates a variable number of regex matches per break position (one per rule until a match is found). For break types with many rules (line break has 50+ rules), this can be slower per character, though the regex engine is highly optimised in Erlang/OTP.

* **Locale resolution.** ICU uses its own locale resolution with resource bundle fallback. `unicode_string` accepts atoms, strings, and `Localize.LanguageTag` structs, with explicit ancestor locale merging for segmentation rules.

## Unicode Version

Rules and property data correspond to Unicode 16.0 / CLDR 46.
