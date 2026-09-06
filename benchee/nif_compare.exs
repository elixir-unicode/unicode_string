# Three-way comparison of segmentation performance.
#
#     UNICODE_STRING_NIF=true mix compile
#     UNICODE_STRING_NIF=true mix run benchee/nif_compare.exs
#
# The three subjects
#
#   native            `Unicode.String.split/2`, the pure Elixir implementation.
#
#   nif (end to end)  `Unicode.String.split/2` with `backend: :nif`. Every call
#                     converts UTF-8 to UTF-16, builds a break iterator, walks
#                     it, converts each segment back to UTF-8 and allocates an
#                     Erlang binary for it. This is what a caller actually pays.
#
#   icu (raw)         The same ICU work with the BEAM boundary excluded:
#                     conversion and iterator construction happen once, before
#                     timing, and the timed call runs whole segmentation passes
#                     inside C. No implementation callable from the BEAM can
#                     beat this, so it is the ceiling rather than an option.
#
# The gap between the second and third columns is the cost of the boundary, and
# it is the number worth knowing before deciding to enable the NIF.
#
# Dictionaries are loaded during warmup, so no native run pays to load one.

unless Unicode.String.Nif.available?() do
  IO.puts("""
  The ICU NIF is not available. Build it with:

      UNICODE_STRING_NIF=true mix compile

  It needs ICU installed — `brew install icu4c` on macOS, `apt install
  libicu-dev` on Debian or Ubuntu.
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
  {"thai words", :word, :th, String.duplicate("สวัสดีเจ้านายทุกคน ", 40)},
  {"mixed script", :word, :ja, String.duplicate("日本語 ISO 8601形式の日付 100 km ", 40)}
]

IO.puts("Warming dictionaries...")

for locale <- [:zh, :ja, :th, :lo, :km, :my] do
  {:ok, _} = Unicode.String.Dictionary.ensure_dictionary_loaded_if_available(locale)
end

for {_name, break, locale, text} <- corpora do
  _ = Unicode.String.split(String.slice(text, 0, 32), break: break, locale: locale)
end

for {name, break, locale, text} <- corpora do
  {:ok, prepared} =
    Unicode.String.Nif.benchmark_prepare(
      text,
      Unicode.String.Nif.break_type(break),
      Atom.to_string(locale)
    )

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
      "icu (raw)" => fn -> Unicode.String.Nif.benchmark_run(prepared, iterations) end
    },
    time: 3,
    warmup: 1,
    print: [configuration: false]
  )
end
