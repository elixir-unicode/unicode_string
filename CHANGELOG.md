# Changelog

## Unicode String v2.4.1

This is the changelog for Unicode String v2.4.1 released on September 20th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Deprecations

* `Unicode.String.Break.Grapheme`, `…Word`, `…Sentence` and `…Line` are deprecated and will be removed in 2.5.0. They have delegated to `Unicode.String.Dfa.*` since 2.4.0 and each function now names 2.5.0 in the warning it emits; the arities match, so migrating is a module rename.

### Performance

* Resolve uncontextual case mappings from a lookup table rather than one generated function clause each, which takes `casing/6` from 4,776 clauses to 37 and a clean compile from 47 seconds to 4.4. Non-ASCII case conversion is roughly 1.4x slower in exchange; ASCII and the locale-specific rules are unchanged.

* Compile the regular expressions that locale-specific casing tests its context with, rather than interpolating them into a sigil at the point of use. An interpolated sigil is not a literal so it recompiled a pattern of roughly 9KB on every character it examined: Greek lower casing is 49x faster, Turkish 46x, and Greek upper casing 11x.

## Unicode String v2.4.0

This is the changelog for Unicode String v2.4.0 released on September 18th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Module changes

Segmentation is now performed by table-driven engines generated from the state machine data published in [PRI #555](https://www.unicode.org/review/pri555/). **The public API is unchanged** — `Unicode.String.split/2`, `next/2`, `stream/2`, `splitter/2`, `break?/2` and the casing functions behave exactly as before, and code using them needs no modification.

Four previously documented modules implemented the annexes by hand. They are now **deprecated shims** that delegate to the generated engines, so existing code keeps working and emits a compiler warning naming its replacement:

| Deprecated | Replacement |
|---|---|
| `Unicode.String.Break.Grapheme` | `Unicode.String.Dfa.Grapheme` |
| `Unicode.String.Break.Word` | `Unicode.String.Dfa.Word` |
| `Unicode.String.Break.Sentence` | `Unicode.String.Dfa.Sentence` |
| `Unicode.String.Break.Line` | `Unicode.String.Dfa.Line` |

Behaviour is unchanged and the arities match — `split/1`, `next/1` and `break?/2` for grapheme, word and line, and `split/3`, `next/3` and `break?/4` for sentence — so migrating is a module rename. The one thing to know is that the former `Unicode.String.Break.Line.split/1` applied the rules alone; that is `Unicode.String.Dfa.Line.rule_split/1`, while `Unicode.String.Dfa.Line.split/1` also runs the dictionary pass for Thai, Lao, Khmer and Burmese.

Line and sentence gain locale-aware variants (`Unicode.String.Dfa.Line.split/2`, `Unicode.String.Dfa.Sentence.split/3`) carrying the CLDR tailoring described below.

These remain internal engines rather than a supported interface; `Unicode.String` is the API to prefer. The shims will be removed in 2.5.0.

Two modules are newly public: `Unicode.String.Dfa`, from which the four break engines are generated, and `Unicode.String.Break.Tailoring`, which holds CLDR's locale tailoring and abbreviation suppressions.

### Enhancements

* Support Unicode 18.0.0. Rule GB9c no longer requires a leading `Indic_Conjunct_Break=Consonant`, so a linker opens a conjunct sequence from any position including the start of text. Segmentation test data is refreshed to 18.0.0.

* Segment all four break types with a table-driven engine generated from the state machine data published in PRI #555. Line breaking now passes all 19,346 cases of `LineBreakTest.txt` where the previous engine passed 99.81%.

* Support CLDR locale tailoring of break classes through `Unicode.String.Break.Tailoring`. Greek sentences break at U+003B and U+037E, and `ja`, `zh` and `zh-Hant` line breaking treats conditional Japanese starters as ideographs rather than non-starters.

* Add an optional ICU4C backend, `Unicode.String.Nif`, selected with `backend: :nif` on `Unicode.String.split/2`. It is opt-in via `UNICODE_STRING_NIF=true` or `config :unicode_string, :nif, true`, requires ICU system libraries and `:elixir_make`, and falls back to the native implementation whenever it is unavailable, so the option is always safe to pass. See the [Conformance guide](guides/conformance.md) for when it is worth enabling — end to end it is 5-7x faster for line breaking and the dictionary locales, but only 1.3-1.5x for word and grapheme breaking.

### Performance

* Skip the dictionary pass in line breaking for text that cannot contain a dictionary script. Thai, Lao, Khmer and Burmese all lie in U+0E01..U+17FF, which UTF-8 encodes with a lead byte of `0xE0` or `0xE1`, and neither byte can occur as a continuation byte, so a single `:binary.match` rules them out. Line breaking is 1.85x faster on Latin text.

* Skip the Unicode property table lookups for Latin-1 codepoints in all four break types. The break class of every codepoint below U+0100 is resolved at compile time into a tuple indexed by codepoint, and below U+00A9 no character is `Extended_Pictographic` or carries an `Indic_Conjunct_Break` value, so grapheme breaking skips those two tests entirely. Measured on 1,800 bytes of Latin text: word breaking 3.8x faster, sentence breaking 3.5x faster, line breaking 1.6x faster and grapheme breaking 1.4x faster.

* Decide grapheme and word boundaries from raw UTF-8 bytes where the answer is certain, without decoding a codepoint or consulting a property table. Two printable ASCII bytes in a row are always a grapheme boundary, and a run of ASCII letters is always a whole word provided the byte ending the run cannot join to it. Both preconditions are computed from the Unicode data at compile time. Grapheme breaking is 4.1x faster and word breaking a further 1.4x on Latin text.

* Compile the `Extended_Pictographic` property into a balanced binary tree of comparisons rather than a flat chain of 156 `or` clauses. Because `or` short-circuits on true, the flat form cost all 156 comparisons for every character that is *not* pictographic, which is almost every character in ordinary text. The tree answers in about 8 and remains valid in a guard.

### Bug Fixes

* Apply a locale's casing rules to the whole string. A character with no rule for the locale switched the remainder to the locale-independent rules, so any later locale-specific mapping was lost — Lithuanian `i` followed by a combining dot above is the case that shows it.

* Implement the casing rules that remove a character. `SpecialCasing.txt` leaves a mapping blank where the character is dropped in that context, which was read as an absent mapping: the combining dot above is now removed when lower casing after a Turkish or Azeri `I`, and when upper or title casing after a Lithuanian soft-dotted letter.

* Apply the Lithuanian dot-above rule to `J` as well as `I`. `J` was excluded from the generated mappings and handled by the ASCII fast path, so it never gained the dot that an accent above requires.

* Fix Turkish and Azeri lower casing of `I` before a combining dot above. `Before_Dot` is a condition on what follows the character, but was being tested against what precedes it, so `I` became dotless `ı` in a sequence where the standard keeps the dotted `i`.

* Fix locale-dependent casing duplicating the start of a string. Where a contextual rule did not apply, the fallback re-cased the character with an accumulator that already held everything mapped so far, emitting that prefix twice. Affected Turkish, Azeri and Lithuanian.

* Keep dictionary-based line breaking inside its own script, so a boundary is added only between two characters of the dictionary script. Adjacent punctuation no longer becomes its own segment, which had broken after an opening bracket where LB14 forbids it and before a closing one where LB13 does.

* Apply the line-break dictionary pass in `Unicode.String.stream/2` and `Unicode.String.splitter/2`. Both previously returned different segments from `Unicode.String.split/2` for Thai, Lao, Khmer and Burmese.

* Complete LB30b with its `[\p{Extended_Pictographic}&\p{Cn}] × EM` alternative, so an unassigned pictographic keeps its emoji modifier. These characters carry `lb=ID` or `lb=XX`, so the rule cannot be expressed in line-break classes alone.

* Implement LB25 in full, tracking the `NU (SY | IS)*` number run it is defined over. Numeric prefixes and postfixes now join only where a number is actually present, so `PO × OP` no longer suppresses a break unless a number follows the open punctuation.

* Implement LB28a, so breaks are suppressed inside the orthographic syllables of Brahmic scripts across the `AP`, `AK`, `AS`, `VI` and `VF` classes and U+25CC DOTTED CIRCLE.

* Implement LB19 and LB19a, so breaks are suppressed only before a non-initial and after a non-final quotation mark, and on both sides of any quotation mark that is not surrounded by East Asian characters. Previously every quotation mark suppressed breaks on both sides unconditionally.

* Implement LB15a and LB15b, so a break is suppressed after an initial (`Pi`) quotation mark across any following spaces, and before a final (`Pf`) quotation mark that ends the text or is followed by space, glue or closing punctuation. This also removes a `QU SP* × OP` rule that no longer exists in UAX #14.

* Apply the LB30 East-Asian-width restriction, so `(AL | HL | NU) × OP` and `CP × (AL | HL | NU)` no longer suppress a break when the punctuation has an `East_Asian_Width` of `F`, `W` or `H`.

* Apply LB10 to a combining mark that begins a segment. A `CM` or `ZWJ` with no base to attach to is now treated as `AL`, where previously it kept class `CM` and admitted a spurious break before the following character.

* Resolve `Line_Break=SA` by General_Category as LB1 requires, to `CM` for `Mn` and `Mc` and to `AL` otherwise. Previously all `SA` resolved to `AL`, which broke sequences such as an ideograph followed by a Thai combining mark.

## Unicode String v2.3.1

This is the changelog for Unicode String v2.3.1 released on August 16th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Word breaking in a dictionary locale now applies the dictionary only to runs of text written in the script(s) that dictionary covers, with the standard Unicode rules governing everything else. Previously `Unicode.String.split("Japanese", break: :word, locale: :ja)` returned each letter separately.

* Word and line breaking no longer raise a `File.Error` when the ICU dictionaries have not been downloaded with `mix unicode.string.download.dictionaries`. Segmentation now falls back to the standard Unicode rules, and `Unicode.String.break/2` and `Unicode.String.splitter/2` return `{:error, reason}`.

## Unicode String v2.3.0

This is the changelog for Unicode String v2.3.0 released on July 23rd, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Enhancements

* Add `Unicode.String.word_like?/1` which returns whether a segment contains alphabetic or numeric content, mirroring the `isWordLike` property of JS `Intl.Segmenter` word segments (ICU's word-break rule status). Apply it to segments returned by `Unicode.String.split/2` with `break: :word`.

## Unicode String v2.2.0

This is the changelog for Unicode String v2.2.0 released on July 9th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Fix an unreachable `can_begin_word?/2` clause that produced a compiler warning under `--warnings-as-errors`.

### Enhancements

* Add Credo (strict) to CI and development, a 90% test coverage gate, and a checked-in `mix format` pre-commit hook.

* Harden the CI workflow: OTP/Elixir-scoped dependency and build caches, refreshed toolchain matrix, and separate lint, coverage and Dialyzer stages.

## Unicode String v2.1.0

This is the changelog for Unicode String v2.1.0 released on May 1st, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Improve line break segmentation conformance and compatibility with ICU.

### Enhancements

* Replaces the regex-based segmentation engine with a single-pass DFA evaluator. Sentence break on a 4 KB unbroken sentence drops from ~9,200 ms to ~11 ms (~840×); word break on a 4 KB sentence from ~7,000 ms to ~12 ms (~580×); scaling is now linear in input length instead of O(N²).

## Unicode String v2.0.1

This is the changelog for Unicode String v2.0.1 released on April 29th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Fix compile + dialyzer + tests without optional :localize dependency.

## Unicode String v2.0.0

This is the changelog for Unicode String v2.0.0 released on April 14th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Breaking change

* Unicode String version 2.0 and later is supported on Elixir 1.17 or later only.

### Enhancements

* Replace `ex_cldr` with `localize` as the localization library

* Fix titalcasing the letter `i` - including correct handling in Turkic languages

* Use `Localize.Locale.best_match/3` for locale matching

* Fixes to the `Unicode.Break` module.

## Unicode String v1.8.0

This is the changelog for Unicode String v1.8.0 released on January 19th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Enhancements

* Updates to [Unicode 17.0](https://unicode.org/versions/Unicode17.0.0/) data.

## Unicode String v1.7.0

This is the changelog for Unicode String v1.7.0 released on March 29th, 2025.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Converts all compile-time regex compilation to runtime to be compatible with OTP 28.

## Unicode String v1.6.0

This is the changelog for Unicode String v1.6.0 released on March 17th, 2025.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Fix word break detection when a `\p{word_break=extend}` codepoint is preceeded by a letter and followed by a letter.

### Enhancements

* Updated to [CLDR 47](https://cldr.unicode.org/downloads/cldr-47) break rules and test data.

## Unicode String v1.5.0

This is the changelog for Unicode String v1.5.0 released on January 1st, 2025.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Enhancements

* Update to CLDR 46.1 segmentation data and tests.

* Pass dialyzer with `:underspecs` flag set.

## Unicode String v1.4.1

This is the changelog for Unicode String v1.4.1 released on March 14th, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Fix performance regressing in `Uncode.String.Break.next/4`. Added the script `bench/next.exs` to allow for regression testing. Thanks to @mntns for the report. Closes #6.

## Unicode String v1.4.0

This is the changelog for Unicode String v1.4.0 released on March 10th, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Enhancements

* Adds dictionary-based work breaking for Chinese (zh, zh-Hant, zh-Hans, zh-Hant-HK, yue, yue-Hans), Japanese (ja), Thai (th), Lao (lo), Khmer (km) and Burmese (my). These languages don't typically use whitespace to separate words so a dictionary lookup is more appropriate - although not perfect.  The same dictionary is used for Chinese and Japanese. The dictionaries implemented are those used in the [CLDR](https://cldr.unicode.org) since they are under an open source license and also for consistency with [ICU](https://icu.unicode.org). Note that these dictionaries need to be downloaded with `mix unicode.string.download.dictionaries` prior to use. Each dictionary will be parsed and loaded into [persistent_term](https://www.erlang.org/doc/man/persistent_term) on demand. Each dictionary has a sizable memory footprint as measured by `:persistent_term.info/0`:

| Dictionary  | Memory Mb   |
| ----------- | ----------: |
| Chinese     | 104.8       |
| Thai        | 9.6         |
| Lao         | 11.4        |
| Khmer       | 38.8        |
| Burmese     | 23.1        |

## Unicode String v1.3.1

This is the changelog for Unicode String v1.3.1 released on March 6th, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Fix `Unicode.String.split/2` and `Unicode.String.next/2` when the passing rule is `:no_break` rule. Thanks to @GregLMcDonald for the report. Closes #5.

## Unicode String v1.3.0

This is the changelog for Unicode String v1.3.0 released on February 27th, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Fix case folding for codepoints that fold to themselves.

### Enhancements

* Adds case mapping functions `Unicode.String.upcase/2`, `Unicode.String.downcase/2` and `Unicode/String.titlecase/2`. These functions implement the full [Unicode Casing algorithm](https://www.unicode.org/versions/Unicode15.0.0/ch03.pdf) including conditiional mappings. They are locale-aware and a locale can be specified as a string, atom or a [Cldr.LanguageTag](https://hexdocs.pm/ex_cldr/Cldr.LanguageTag.html) thereby providing basic integration between `unicode_string` and [ex_cldr](https://hex.pm/packages/ex_cldr).

* Case folding always follows the `:full` path which allows mapping of single code points to multiple code points. There is no practical reason to implement the `:simple` path. As a result, the `type` parameter to `Unicode.String.Case.Folding.fold/2` is no longer required or supported.

* Support an [ex_cldr](https://hex.pm/packages/ex_cldr) [Language Tag](https://hexdocs.pm/ex_cldr/Cldr.LanguageTag.html) as a parameter to `Unicode.String.Case.Folding.fold/2`. In fact any map that has a `:language` key with a value that is an [ISO 639-1](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes) language code as a lower cased atom may be passed as a parameter.

## Unicode String v1.2.1

This is the changelog for Unicode String v1.2.1 released on June 2nd, 2023.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Resolve segments dir at runtime, not compile time. Thanks to @crkent for the report. Closes #4.

## Unicode String v1.2.0

This is the changelog for Unicode String v1.2.0 released on March 14th, 2023.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Enhancements

* Adds `Unicode.String.stream/2` to support streaming graphemes, words, sentences and line breaks.

## Unicode String v1.1.0

This is the changelog for Unicode String v1.1.0 released on September 21st, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Enhancements

* Updates the segmentation supplemental data (including locales) for CLDR. This adds the "sv" and "fi" locale data for sentence break suppressions.

## Unicode String v1.0.1

This is the changelog for Unicode String v1.0.1 released on September 15th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Woops, the priv/segments directory was not included in the build artifact

## Unicode String v1.0.0

This is the changelog for Unicode String v1.0.0 released on September 14th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Enhancements

* Update to use [Unicode 14](https://unicode.org/versions/Unicode14.0.0) release data.

## Unicode String v0.3.0

This is the changelog for Unicode String v0.3.0 released on October 11th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Correct deps and docs to align with Elixir 1.11 and recent releases of `ex_unicode`.

# Unicode String v0.2.0

This is the changelog for Unicode String v0.2.0 released on July 12th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Enhancements

This release implements the Unicode break rules for graphemes, words, lines (word-wrapping) and sentences.

* Adds `Unicode.String.split/2`

* Adds `Unicode.String.break?/2`

* Adds `Unicode.String.break/2`

* Adds `Unicode.String.splitter/2`

* Adds `Unicode.String.next/2`

# Unicode String v0.1.0

This is the changelog for Unicode String v0.1.0 released on May 17th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Enhancements

* Initial release
