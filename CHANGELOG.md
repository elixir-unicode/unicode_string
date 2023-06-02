# Changelog

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
