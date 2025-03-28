# Changelog

## Unicode String v1.7.0

This is the changelog for Unicode String v1.7.0 released on March 29th.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

### Bug Fixes

* Converts all compile-time regex compilation to runtime to be compatible with OTP 28. Performance implications are not yet known.

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
