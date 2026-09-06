# Three-way comparison: native Elixir, the ICU NIF as a consumer actually calls
# it, and ICU with the BEAM boundary excluded.
#
#     benchee/icu/build.sh
#     UNICODE_STRING_NIF=true mix compile
#     UNICODE_STRING_NIF=true mix run benchee/nif_compare.exs
#
# The three subjects
#
#   native            `Unicode.String.split/2`.
#
#   nif (end to end)  `Unicode.String.split/2` with `backend: :nif`. Every call
#                     converts UTF-8 to UTF-16, builds a break iterator, walks
#                     it, converts each segment back to UTF-8 and allocates an
#                     Erlang binary for it. This is what a caller pays.
#
#   icu (raw)         The same ICU work with all of that excluded: conversion
#                     and iterator construction happen once, up front, and the
#                     timed call runs the iteration inside C. It is the ceiling
#                     ICU could reach if the boundary were free, and no
#                     implementation callable from the BEAM can beat it.
#
# The gap between the second and third is the price of the boundary, which is
# the number worth knowing before adopting the NIF.
#
# Dictionaries are warmed before timing so no native run pays to load one.

defmodule IcuBreak do
  @on_load :load_nif
  @nif_path Path.join(__DIR__, "icu/icu_break") |> String.to_charlist()

  def load_nif, do: :erlang.load_nif(@nif_path, 0)
  def prepare(_text, _type, _locale), do: :erlang.nif_error(:not_loaded)
  def run(_resource, _iterations), do: :erlang.nif_error(:not_loaded)
  def run_extract(_resource, _iterations), do: :erlang.nif_error(:not_loaded)

  def type(:grapheme), do: 0
  def type(:word), do: 1
  def type(:line), do: 2
  def type(:sentence), do: 3
end

unless Unicode.String.Nif.available?() do
  IO.puts("""
  The ICU NIF is not available. Build it with:

      UNICODE_STRING_NIF=true mix compile
  """)

  System.halt(1)
end

iterations = 25

corpora = [
  {"english prose", :word, :en,
   String.duplicate("The quick brown fox jumps over the lazy dog. ", 40)},
  {"english lines", :line, :en,
   String.duplicate("The quick brown fox jumps over the lazy dog. ", 40)},
  {"english graphemes", :grapheme, :en,
   String.duplicate("The quick brown fox jumps over the lazy dog. ", 40)},
  {"english sentences", :sentence, :en,
   String.duplicate("The quick brown fox jumps over the lazy dog. ", 40)},
  {"japanese words", :word, :ja, String.duplicate("日本語のテキストです。これはテストです。", 40)},
  {"thai words", :word, :th, String.duplicate("สวัสดีเจ้านายทุกคน ", 40)}
]

IO.puts("Warming dictionaries...")

for locale <- [:zh, :ja, :th, :lo, :km, :my] do
  {:ok, _} = Unicode.String.Dictionary.ensure_dictionary_loaded_if_available(locale)
end

for {_name, break, locale, text} <- corpora do
  _ = Unicode.String.split(String.slice(text, 0, 32), break: break, locale: locale)
end

for {name, break, locale, text} <- corpora do
  {:ok, resource} = IcuBreak.prepare(text, IcuBreak.type(break), Atom.to_string(locale))

  IO.puts("""

  ══════════════════════════════════════════════════════════════════
   #{name} — break: #{break}, locale: #{locale}, #{byte_size(text)} bytes
   #{iterations} segmentation passes per timed call
  ══════════════════════════════════════════════════════════════════
  """)

  Benchee.run(
    %{
      "native" => fn ->
        Enum.each(1..iterations, fn _ ->
          Unicode.String.split(text, break: break, locale: locale)
        end)
      end,
      "nif (end to end)" => fn ->
        Enum.each(1..iterations, fn _ ->
          Unicode.String.split(text, break: break, locale: locale, backend: :nif)
        end)
      end,
      "icu (raw)" => fn -> IcuBreak.run_extract(resource, iterations) end
    },
    time: 3,
    warmup: 1,
    print: [configuration: false]
  )
end
