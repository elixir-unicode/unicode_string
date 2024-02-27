# Changelog

## Unicode String v1.3.0

This is the changelog for Unicode String v1.3.0 released on Fabruary 27th, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-unicode/unicode_string/tags)

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
