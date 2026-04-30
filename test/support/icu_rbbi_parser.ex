defmodule Unicode.String.IcuRbbiParser do
  @moduledoc false

  # Parser for ICU's `rbbitst.txt` boundary-iterator test corpus.
  #
  # The file format is documented at the top of rbbitst.txt; see also
  # https://github.com/unicode-org/icu/blob/main/icu4c/source/test/testdata/rbbitst.txt
  #
  # We extract `<data>…</data>` blocks under each `<sent>`, `<line>`,
  # `<word>`, or `<char>` mode marker, attaching the most recent
  # `<locale …>` to each. Within a data block, `•` (U+2022), `<>`, or
  # `<NNN>` mark expected break positions; ICU-style backslash escapes
  # (`\u…`, `\\`, `\<`, `\n`, `\r`, `\t`, …) are decoded; a backslash
  # at end-of-line continues to the next physical line.
  #
  # Returns a list of `%{mode: :sent | :line | :word | :char,
  #                      locale: binary, suppressions?: boolean,
  #                      input: binary, expected: [binary]}` maps.

  @break_modes ~w(sent line word char title)a

  defguardp is_hex(c)
            when c in ?0..?9 or c in ?a..?f or c in ?A..?F

  @spec parse(Path.t()) :: [map]
  def parse(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> strip_comments_and_blank_lines()
    |> join_continuations()
    |> drop_inline_comments()
    |> stream_blocks()
    |> Enum.flat_map(&maybe_parse_data/1)
  end

  ## --- Pre-processing -------------------------------------------------------

  # Drop full-line comments (lines starting with optional whitespace + `#`)
  # and pure blank lines. Leave the rest as a list of physical lines.
  defp strip_comments_and_blank_lines(lines) do
    Enum.reject(lines, fn line ->
      trimmed = String.trim_leading(line)
      trimmed == "" or String.starts_with?(trimmed, "#")
    end)
  end

  # Join physical lines ending in a backslash to the next line.
  defp join_continuations(lines), do: do_join(lines, [])

  defp do_join([], acc), do: Enum.reverse(acc)

  defp do_join([line | rest], acc) do
    if String.ends_with?(line, "\\") do
      head = binary_part(line, 0, byte_size(line) - 1)

      case rest do
        [next | rest2] -> do_join([head <> next | rest2], acc)
        [] -> Enum.reverse([head | acc])
      end
    else
      do_join(rest, [line | acc])
    end
  end

  # Trim trailing inline comments ("# ..." after at least one space)
  # while preserving content within `<data>` blocks.
  defp drop_inline_comments(lines) do
    Enum.map(lines, fn line ->
      cond do
        String.contains?(line, "<data>") and not String.contains?(line, "</data>") ->
          line

        String.contains?(line, "</data>") ->
          # Trim trailing `# …` after `</data>`.
          [pre, post] = String.split(line, "</data>", parts: 2)
          pre <> "</data>" <> drop_trailing_comment(post)

        true ->
          drop_trailing_comment(line)
      end
    end)
  end

  defp drop_trailing_comment(line) do
    # Cut from the first ` #` that's not inside a tag context.
    case Regex.run(~r/\s+#.*$/, line) do
      [match] -> String.replace_trailing(line, match, "")
      _ -> line
    end
  end

  ## --- Streaming blocks -----------------------------------------------------

  # Walk through the joined lines maintaining mode/locale state and
  # emit each `<data>…</data>` block as a tuple.
  defp stream_blocks(lines) do
    Enum.reduce(lines, %{mode: nil, locale: "root", blocks: []}, fn line, state ->
      cond do
        m = Regex.run(~r/^\s*<locale\s+([^>]+)>/, line) ->
          %{state | locale: hd(tl(m))}

        m = Regex.run(~r/^\s*<(sent|line|word|char|title)>/, line) ->
          %{state | mode: String.to_atom(hd(tl(m)))}

        Regex.match?(~r/<rules>/, line) ->
          # Skip rules-overrides — we test against the standard rules.
          state

        m = Regex.run(~r/^\s*<data>(.*)<\/data>\s*$/, line) ->
          [_, body] = m

          if state.mode in @break_modes do
            %{state | blocks: [{state.mode, state.locale, body} | state.blocks]}
          else
            state
          end

        true ->
          state
      end
    end)
    |> Map.fetch!(:blocks)
    |> Enum.reverse()
  end

  ## --- Per-block parsing ----------------------------------------------------

  defp maybe_parse_data({mode, locale_spec, body}) do
    {locale, suppressions?} = parse_locale_spec(locale_spec)

    case parse_body(body) do
      {:ok, input, expected} ->
        [
          %{
            mode: mode,
            locale: locale,
            suppressions?: suppressions?,
            input: input,
            expected: expected
          }
        ]

      :skip ->
        []
    end
  end

  defp parse_locale_spec(spec) do
    {locale, attrs} =
      case String.split(spec, "@", parts: 2) do
        [l] -> {l, ""}
        [l, a] -> {l, a}
      end

    suppressions? = String.contains?(attrs, "ss=standard")
    {String.trim(locale), suppressions?}
  end

  # Walk the body, splitting at break markers and decoding escapes.
  # Returns {:ok, input, expected_segments} or :skip.
  defp parse_body(body) do
    do_parse(body, [], "", "")
  rescue
    _ -> :skip
  end

  defp do_parse("", segs, current, input) do
    expected =
      case current do
        "" -> Enum.reverse(segs)
        _ -> Enum.reverse([current | segs])
      end

    # If the body ended without a final break marker we treat the
    # last accumulated chunk as a final segment.
    {:ok, input, Enum.reject(expected, &(&1 == ""))}
  end

  # Break markers
  defp do_parse(<<"•"::utf8, rest::binary>>, segs, current, input) do
    flush(rest, segs, current, input)
  end

  defp do_parse(<<"<>", rest::binary>>, segs, current, input) do
    flush(rest, segs, current, input)
  end

  defp do_parse(<<"<", _, _::binary>> = bin, segs, current, input) do
    case Regex.run(~r/^<(\d+)>(.*)$/s, bin) do
      [_, _status, rest] -> flush(rest, segs, current, input)
      _ -> append_literal(bin, segs, current, input)
    end
  end

  # Backslash escapes
  defp do_parse(<<"\\u", a, b, c, d, rest::binary>>, segs, current, input)
       when is_hex(a) and is_hex(b) and is_hex(c) and is_hex(d) do
    cp = String.to_integer(<<a, b, c, d>>, 16)
    handle_escaped_codepoint(cp, rest, segs, current, input)
  end

  defp do_parse(<<"\\U", a, b, c, d, e, f, g, h, rest::binary>>, segs, current, input)
       when is_hex(a) and is_hex(b) and is_hex(c) and is_hex(d) and
              is_hex(e) and is_hex(f) and is_hex(g) and is_hex(h) do
    cp = String.to_integer(<<a, b, c, d, e, f, g, h>>, 16)
    handle_escaped_codepoint(cp, rest, segs, current, input)
  end

  defp do_parse(<<"\\x", a, b, rest::binary>>, segs, current, input)
       when is_hex(a) and is_hex(b) do
    cp = String.to_integer(<<a, b>>, 16)
    ch = <<cp::utf8>>
    do_parse(rest, segs, current <> ch, input <> ch)
  end

  # An escaped U+2022 (BULLET) acts as a break marker, just like a raw •.
  defp do_parse(<<"\\\\", rest::binary>>, segs, current, input),
    do: do_parse(rest, segs, current <> "\\", input <> "\\")

  defp do_parse(<<"\\n", rest::binary>>, segs, current, input),
    do: do_parse(rest, segs, current <> "\n", input <> "\n")

  defp do_parse(<<"\\r", rest::binary>>, segs, current, input),
    do: do_parse(rest, segs, current <> "\r", input <> "\r")

  defp do_parse(<<"\\t", rest::binary>>, segs, current, input),
    do: do_parse(rest, segs, current <> "\t", input <> "\t")

  defp do_parse(<<"\\f", rest::binary>>, segs, current, input),
    do: do_parse(rest, segs, current <> "\f", input <> "\f")

  # Escape any other character literally (covers \<, \>, etc.)
  defp do_parse(<<"\\", ch::utf8, rest::binary>>, segs, current, input) do
    s = <<ch::utf8>>
    do_parse(rest, segs, current <> s, input <> s)
  end

  defp do_parse(<<ch::utf8, rest::binary>>, segs, current, input) do
    s = <<ch::utf8>>
    do_parse(rest, segs, current <> s, input <> s)
  end

  # An escaped U+2022 (BULLET) acts as a break marker, just like a raw •.
  defp handle_escaped_codepoint(0x2022, rest, segs, current, input) do
    flush(rest, segs, current, input)
  end

  defp handle_escaped_codepoint(cp, rest, segs, current, input) do
    ch = <<cp::utf8>>
    do_parse(rest, segs, current <> ch, input <> ch)
  end

  defp append_literal(<<ch::utf8, rest::binary>>, segs, current, input) do
    s = <<ch::utf8>>
    do_parse(rest, segs, current <> s, input <> s)
  end

  defp flush(rest, segs, "", input), do: do_parse(rest, segs, "", input)

  defp flush(rest, segs, current, input),
    do: do_parse(rest, [current | segs], "", input)
end
