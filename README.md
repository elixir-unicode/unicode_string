# Unicode String

Adds functions supporting some string algorithms in the Unicode standard.

In this initial release the following functions are defined:

* `Unicode.String.fold/1,2` that applies the [Unicode Case Folding algorithm](https://www.unicode.org/versions/Unicode14.0.0/ch03.pdf)

* `Unicode.String.equals_ignoring_case?/2` that compares two strings for equality after applying `Unicode.String.fold/2` to the arguments.

## Examples

		iex> Unicode.String.equals_ignoring_case? "ABC", "abc"
		true

		iex> Unicode.String.equals_ignoring_case? "beißen", "beissen"
		true

		iex> Unicode.String.equals_ignoring_case? "grüßen", "grussen"
		false

## Installation

The package can be installed by adding `unicode_string` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:unicode_string, "~> 1.0"}
  ]
end
```

