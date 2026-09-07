defmodule Unicode.String.Dfa do
  @moduledoc """
  The break-iteration algorithm described in PRI #555 (L2/26-135), section 9.3.2.

  A break type is realised by `use`-ing this module with the name of the data
  files to compile in:

      defmodule Unicode.String.Dfa.Grapheme do
        use Unicode.String.Dfa, type: "GraphemeClusterBreak"
      end

  The automaton recognises the language between one break and the next: it runs
  from the last break, remembering the most recent accepting position, and when
  no transition exists it reports that position as the next break. Lookaheads,
  which only the line break machine uses, let a state report a position recorded
  earlier rather than the last accepting one.

  No rule of the annex appears as code here. The rules live in the data files
  read by `Unicode.String.Dfa.Builder`, which is what makes adopting a new
  Unicode version a data update rather than a re-reading of the rules.
  """

  defmacro __using__(options) do
    type = Keyword.fetch!(options, :type)
    data = Unicode.String.Dfa.Builder.read(type)
    pair_breaks = Unicode.String.Dfa.Builder.ascii_pair_breaks(data)

    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote bind_quoted: [
            data: Macro.escape(data),
            pair_breaks: Macro.escape(pair_breaks),
            options: Macro.escape(options)
          ] do
      # The engine is generic but each module's tables are fixed, so branches
      # that another break type needs are unreachable here. That is inherent to
      # generating code from data and is not worth contorting the engine for.
      @dialyzer :no_match

      @symbol_ranges data.symbol_ranges
      @symbol_range_count tuple_size(@symbol_ranges)

      # The symbol of every Latin-1 codepoint is known at compile time, so the
      # binary search is replaced by a single tuple index for the bulk of
      # ordinary Western text. This mirrors the Latin-1 class tables the
      # direct-coded rule engines use, so the two are compared on equal footing.
      @latin1_limit 0x100
      @latin1_symbols 0..(@latin1_limit - 1)
                      |> Enum.map(fn codepoint ->
                        Enum.find_value(Tuple.to_list(data.symbol_ranges), fn {from, to, symbol} ->
                          codepoint >= from and codepoint <= to and symbol
                        end)
                      end)
                      |> List.to_tuple()

      # Only the line break machine uses lookaheads. Where none exist the map
      # that carries them is never read, so it is not built.
      # Several break types define dictionary symbols, but the post-pass applied
      # here is the line-break one, so it is only correct for line breaking.
      # Word breaking triggers its dictionary differently — the run is handed to
      # the dictionary in place of the rules, rather than after them — so it is
      # opted in explicitly rather than inferred from the presence of symbols.
      @dictionary_pass Keyword.get(options, :dictionary_pass, false)

      @uses_lookaheads data.states
                       |> Tuple.to_list()
                       |> Enum.any?(fn {accepting, lookahead, _} ->
                         lookahead != nil or match?({:lookahead, _}, accepting)
                       end)
      @states data.states
      @transitions data.transitions
      @start_state data.start_state
      @eot_symbol data.eot_symbol

      @doc false
      def symbol_count, do: unquote(data.symbol_count)

      @doc false
      def state_count, do: unquote(data.state_count)

      @ascii_pair_breaks pair_breaks

      @doc "Returns `{segment, rest}`, or `nil` when `string` is empty."
      def next(""), do: nil

      # Where the machine has no lookaheads, whether it breaks after the first
      # of two ASCII characters is fixed at compile time, so the common Latin
      # case needs one tuple index and no decoding at all. Both returned
      # binaries are sub-binaries of the input, so nothing is copied.
      if @ascii_pair_breaks do
        def next(<<first, second, _rest::binary>> = string)
            when first < 0x80 and second < 0x80 and
                   :erlang.element(first * 0x80 + second + 1, @ascii_pair_breaks) do
          {binary_part(string, 0, 1), binary_part(string, 1, byte_size(string) - 1)}
        end
      end

      def next(string) do
        {length, break_type} = next_boundary(string)
        _ = break_type
        {binary_part(string, 0, length), binary_part(string, length, byte_size(string) - length)}
      end

      @doc """
      Splits `string` into segments.

      Where the data defines dictionary symbols, the rule-based segments are
      passed through the dictionary breaker afterwards, which is how the
      standard describes complex context-dependent breaking being triggered.
      """
      def split(""), do: []

      if @dictionary_pass do
        def split(string) do
          string |> rule_split() |> Enum.flat_map(&Unicode.String.Break.dict_subsplit_line/1)
        end
      else
        def split(string), do: rule_split(string)
      end

      @doc "Splits `string` using the rules alone, without the dictionary pass."
      def rule_split(""), do: []

      def rule_split(string) do
        {segment, rest} = next(string)
        [segment | rule_split(rest)]
      end

      @doc """
      Returns `true` when a segment boundary falls between `string_before` and
      `string_after`.

      The automaton always restarts at a boundary, so the question "is there a
      break at this join" is answered by segmenting from the start of the
      combined text and asking whether any boundary lands exactly on the join.
      """
      def break?("", _string_after), do: true
      def break?(_string_before, ""), do: true

      def break?(string_before, string_after) do
        boundary_at?(string_before <> string_after, byte_size(string_before))
      end

      # `target` is the byte offset the join sits at, counted from the start of
      # whatever remains. A boundary landing past it means the join is inside a
      # segment and there is no break there.
      defp boundary_at?(_string, 0), do: true

      defp boundary_at?(string, target) do
        {segment, rest} = next(string)
        length = byte_size(segment)

        cond do
          length == target -> true
          length > target -> false
          true -> boundary_at?(rest, target - length)
        end
      end

      # Runs the automaton from the start of `string` and returns the byte
      # length of the first segment together with its break type.
      defp next_boundary(<<codepoint::utf8, _rest::binary>> = string) do
        # When the machine accepts nothing at all, the segment is still one whole
        # character. The floor has to be that character's byte length: one byte
        # would split a multi-byte codepoint and leave the remainder of the
        # string starting mid-character.
        run(string, @start_state, 0, 0, nil, %{}, byte_size_utf8(codepoint))
      end

      # `taken` is the number of bytes consumed so far, `accepting` the byte
      # length of the most recent accepting position, and `lookaheads` maps a
      # lookahead index to a byte length recorded earlier.
      defp run(remaining, state, taken, accepting, break_type, lookaheads, floor) do
        {symbol, advanced, rest} = next_symbol(remaining, taken)

        case transition(state, symbol) do
          nil -> {max(accepting, floor), break_type}
          next_state -> step(rest, next_state, advanced, accepting, break_type, lookaheads, floor)
        end
      end

      # Having moved to `state`, either report a position recorded earlier by a
      # lookahead, record this one because the state accepts, or carry on.
      defp step(rest, state, advanced, accepting, break_type, lookaheads, floor) do
        {accepting_value, lookahead, state_break_type} = elem(@states, state)

        case resolve(accepting_value, lookaheads) do
          {:done, position} ->
            {position, state_break_type}

          :accept ->
            continue(
              rest,
              state,
              advanced,
              advanced,
              state_break_type,
              lookaheads,
              lookahead,
              floor
            )

          :continue ->
            continue(rest, state, advanced, accepting, break_type, lookaheads, lookahead, floor)
        end
      end

      defp resolve(:yes, _lookaheads), do: :accept
      defp resolve(:no, _lookaheads), do: :continue

      defp resolve({:lookahead, index}, lookaheads) do
        case lookaheads do
          %{^index => position} -> {:done, position}
          _other -> :continue
        end
      end

      defp continue(rest, state, taken, accepting, break_type, lookaheads, lookahead, floor) do
        lookaheads =
          if @uses_lookaheads and lookahead do
            Map.put(lookaheads, lookahead, taken)
          else
            lookaheads
          end

        # With no eot symbol to feed it, the machine simply stops at the end of
        # the text and reports the last accepting position — not everything it
        # consumed, which would swallow a trailing non-accepting run such as the
        # colon in "a:".
        if rest == "" and @eot_symbol == nil do
          {max(accepting, floor), break_type}
        else
          run(rest, state, taken, accepting, break_type, lookaheads, floor)
        end
      end

      # At the end of the text the machine is fed the symbol containing the
      # string "eot" when the data defines one; otherwise the run simply ends.
      defp next_symbol("", taken), do: {@eot_symbol, taken, ""}

      defp next_symbol(<<codepoint::utf8, rest::binary>>, taken) do
        {symbol_of(codepoint), taken + byte_size_utf8(codepoint), rest}
      end

      defp transition(_state, nil), do: nil

      defp transition(state, symbol) do
        @transitions |> elem(state) |> elem(symbol)
      end

      # The symbols partition the code space, so a binary search over the sorted
      # ranges always finds exactly one.
      defp symbol_of(codepoint) when codepoint < @latin1_limit do
        elem(@latin1_symbols, codepoint)
      end

      defp symbol_of(codepoint), do: search(codepoint, 0, @symbol_range_count - 1)

      defp search(_codepoint, low, high) when low > high, do: nil

      defp search(codepoint, low, high) do
        middle = div(low + high, 2)
        {from, to, symbol} = elem(@symbol_ranges, middle)

        cond do
          codepoint < from -> search(codepoint, low, middle - 1)
          codepoint > to -> search(codepoint, middle + 1, high)
          true -> symbol
        end
      end

      defp byte_size_utf8(codepoint) when codepoint < 0x80, do: 1
      defp byte_size_utf8(codepoint) when codepoint < 0x800, do: 2
      defp byte_size_utf8(codepoint) when codepoint < 0x10000, do: 3
      defp byte_size_utf8(_codepoint), do: 4
    end
  end
end
