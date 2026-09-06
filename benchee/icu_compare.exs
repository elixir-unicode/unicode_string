# Compares this library's segmentation against ICU4C's break iterator.
#
#     benchee/icu/build.sh && mix run benchee/icu_compare.exs
#
# Measurement notes
#
#   * ICU's UTF-8 to UTF-16 conversion and iterator construction happen once,
#     in `IcuBreak.prepare/3`, and are never timed. Each timed call then runs
#     @iterations complete passes inside C, so the single NIF boundary crossing
#     is amortised across all of them rather than being charged to ICU.
#
#   * The native side runs the same @iterations passes per timed call, and the
#     dictionaries every dictionary locale needs are loaded during warmup, so
#     no run pays a one-off `File.read` or trie build.
#
#   * Two ICU figures are reported. "icu (boundaries)" walks break positions
#     only. "icu (extract)" also converts each segment back to UTF-8, which is
#     closer to what `Unicode.String.split/2` does. The native implementation
#     additionally allocates an Erlang binary per segment, which neither ICU
#     figure pays for, so treat "icu (extract)" as the fairer of the two and
#     still favourable to ICU.

defmodule IcuBreak do
  @on_load :load_nif
  @nif_path Path.join(__DIR__, "icu/icu_break") |> String.to_charlist()

  def load_nif, do: :erlang.load_nif(@nif_path, 0)
  def prepare(_text, _type, _locale), do: :erlang.nif_error(:not_loaded)
  def run(_resource, _iterations), do: :erlang.nif_error(:not_loaded)
  def run_extract(_resource, _iterations), do: :erlang.nif_error(:not_loaded)

  # UBreakIteratorType from unicode/ubrk.h
  def type(:grapheme), do: 0
  def type(:word), do: 1
  def type(:line), do: 2
  def type(:sentence), do: 3
end

iterations = 25

corpora = [
  {"english prose", :word, "en",
   String.duplicate("The quick brown fox jumps over the lazy dog. ", 40)},
  {"english lines", :line, "en",
   String.duplicate("The quick brown fox jumps over the lazy dog. ", 40)},
  {"english graphemes", :grapheme, "en",
   String.duplicate("The quick brown fox jumps over the lazy dog. ", 40)},
  {"english sentences", :sentence, "en",
   String.duplicate("The quick brown fox jumps over the lazy dog. ", 40)},
  {"japanese words", :word, "ja", String.duplicate("日本語のテキストです。これはテストです。", 40)},
  {"thai words", :word, "th", String.duplicate("สวัสดีเจ้านายทุกคน ", 40)},
  {"mixed script", :word, "ja", String.duplicate("日本語 ISO 8601形式の日付 100 km ", 40)}
]

# (b) Warm the dictionaries so no timed run pays for loading one.
IO.puts("Warming dictionaries...")

for locale <- [:zh, :ja, :th, :lo, :km, :my] do
  {:ok, _} = Unicode.String.Dictionary.ensure_dictionary_loaded_if_available(locale)
end

# Warm the segmentation paths themselves too.
for {_name, break, locale, text} <- corpora do
  _ = Unicode.String.split(String.slice(text, 0, 32), break: break, locale: locale)
end

IO.puts(
  "Dictionaries loaded: #{inspect(Enum.filter([:zh, :th, :lo, :km, :my], &Unicode.String.Dictionary.loaded?/1))}\n"
)

for {name, break, locale, text} <- corpora do
  {:ok, resource} = IcuBreak.prepare(text, IcuBreak.type(break), locale)

  IO.puts("""

  ══════════════════════════════════════════════════════════════════
   #{name} — break: #{break}, locale: #{locale}, #{byte_size(text)} bytes
   #{iterations} segmentation passes per timed call
  ══════════════════════════════════════════════════════════════════
  """)

  Benchee.run(
    %{
      "unicode_string" => fn ->
        Enum.each(1..iterations, fn _ ->
          Unicode.String.split(text, break: break, locale: locale)
        end)
      end,
      "icu (boundaries)" => fn -> IcuBreak.run(resource, iterations) end,
      "icu (extract)" => fn -> IcuBreak.run_extract(resource, iterations) end
    },
    time: 3,
    warmup: 1,
    print: [configuration: false]
  )
end
