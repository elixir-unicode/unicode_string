defmodule Unicode.String.Dfa.Builder do
  @moduledoc false

  # Compile-time reader for the break-iterator state machine data proposed in
  # PRI #555 (L2/26-135). Three files describe each break type:
  #
  #   <Type>Symbols.txt      symbol name ; UnicodeSet ; non-dictionary equivalent
  #   <Type>States.txt       state name ; accepting ; lookahead ; break type
  #   <Type>Transitions.txt  from state ; symbol ; to state
  #
  # Names are explicitly opaque in the proposal, so everything is reduced to
  # integer indices here and the names are kept only for diagnostics.

  @data_dir "pri555/18.0.0"

  @doc false
  def read(type) do
    symbols = read_symbols(type)
    states = read_states(type)
    transitions = read_transitions(type, symbols, states)

    %{
      symbol_names: Enum.map(symbols, & &1.name) |> List.to_tuple(),
      symbol_ranges: symbol_ranges(symbols),
      eot_symbol: string_symbol(symbols, "eot"),
      states: state_table(states),
      start_state: index_of(states, "START"),
      transitions: transitions,
      state_count: length(states),
      symbol_count: length(symbols),
      dictionary_symbols: symbols |> Enum.filter(& &1.non_dictionary) |> Enum.map(& &1.index)
    }
  end

  defp path(type, part) do
    Path.join([:code.priv_dir(:unicode_string) |> to_string(), @data_dir, "#{type}#{part}.txt"])
  end

  defp lines(file) do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.map(fn line -> line |> String.split(";") |> Enum.map(&String.trim/1) end)
  end

  # ---- symbols ------------------------------------------------------------

  defp read_symbols(type) do
    type
    |> path("Symbols")
    |> lines()
    |> Enum.with_index()
    |> Enum.map(fn {fields, index} ->
      [name, expression | rest] = fields
      {ranges, strings} = expand(expression)

      %{
        index: index,
        name: name,
        ranges: ranges,
        strings: strings,
        non_dictionary: List.first(rest) |> blank_to_nil()
      }
    end)
  end

  # A symbol is a UnicodeSet which may hold both codepoints and multi-character
  # strings. The strings carry the end-of-text marker and the shadow symbols
  # used for tailoring; only the codepoints take part in the range table.
  defp expand(expression) do
    {:in, entries} = Unicode.Set.parse_and_reduce!(expression).parsed

    Enum.reduce(entries, {[], []}, fn
      {from, to}, {ranges, strings} when is_integer(from) and is_integer(to) ->
        {[{from, to} | ranges], strings}

      {string, _}, {ranges, strings} when is_list(string) ->
        {ranges, [List.to_string(string) | strings]}
    end)
  end

  defp symbol_ranges(symbols) do
    symbols
    |> Enum.flat_map(fn symbol ->
      Enum.map(symbol.ranges, fn {f, t} -> {f, t, symbol.index} end)
    end)
    |> Enum.sort()
    |> verify_partition()
    |> List.to_tuple()
  end

  # The proposal states that the symbols partition the code space. Checking it
  # here turns a bad data file into a compile error rather than a wrong answer.
  defp verify_partition(ranges) do
    _ =
      Enum.reduce(ranges, -1, fn {from, to, _index}, previous ->
        if from <= previous do
          raise "PRI 555 symbol ranges overlap at U+#{Integer.to_string(from, 16)}"
        end

        to
      end)

    ranges
  end

  defp string_symbol(symbols, string) do
    case Enum.find(symbols, fn symbol -> string in symbol.strings end) do
      nil -> nil
      symbol -> symbol.index
    end
  end

  # ---- states -------------------------------------------------------------

  defp read_states(type) do
    type
    |> path("States")
    |> lines()
    |> Enum.with_index()
    |> Enum.map(fn {fields, index} ->
      [name, accepting | rest] = fields
      lookahead = rest |> Enum.at(0) |> blank_to_nil()
      break_type = rest |> Enum.at(1) |> blank_to_nil()

      %{
        index: index,
        name: name,
        accepting: accepting,
        lookahead: lookahead,
        break_type: break_type
      }
    end)
  end

  # `accepting` is Yes, No, or the name of a lookahead. Lookaheads are numbered
  # in order of first appearance so the runtime can key a small map on them.
  defp state_table(states) do
    lookaheads =
      states
      |> Enum.flat_map(fn state -> [state.accepting, state.lookahead] end)
      |> Enum.reject(&(&1 in [nil, "Yes", "No"]))
      |> Enum.uniq()
      |> Enum.with_index()
      |> Map.new()

    states
    |> Enum.map(fn state ->
      accepting =
        case state.accepting do
          "Yes" -> :yes
          "No" -> :no
          name -> {:lookahead, Map.fetch!(lookaheads, name)}
        end

      lookahead = if state.lookahead, do: Map.fetch!(lookaheads, state.lookahead)

      {accepting, lookahead, break_type(state.break_type)}
    end)
    |> List.to_tuple()
  end

  defp break_type(nil), do: nil
  defp break_type("Mandatory"), do: :mandatory
  defp break_type("Letter"), do: :letter
  defp break_type("Number"), do: :number
  defp break_type("Nonterminated"), do: :nonterminated
  defp break_type(other), do: String.to_atom(String.downcase(other))

  # ---- transitions --------------------------------------------------------

  # Stored as a tuple of per-state tuples indexed by symbol, so a transition is
  # two `elem/2` calls. `nil` means no transition, which ends the current run.
  defp read_transitions(type, symbols, states) do
    symbol_index = Map.new(symbols, fn symbol -> {symbol.name, symbol.index} end)
    state_index = Map.new(states, fn state -> {state.name, state.index} end)

    table =
      type
      |> path("Transitions")
      |> lines()
      |> Enum.reduce(%{}, fn [from, symbol, to], acc ->
        Map.put(
          acc,
          {Map.fetch!(state_index, from), Map.fetch!(symbol_index, symbol)},
          Map.fetch!(state_index, to)
        )
      end)

    for state <- 0..(length(states) - 1) do
      for symbol <- 0..(length(symbols) - 1) do
        Map.get(table, {state, symbol})
      end
      |> List.to_tuple()
    end
    |> List.to_tuple()
  end

  @doc false
  # For every pair of ASCII codepoints, whether the machine breaks straight
  # after the first one. That is true when the state reached on the first symbol
  # accepts, and no transition leaves it on the second symbol — exactly the
  # conditions under which the run ends and reports the accepting position.
  #
  # Precomputing it lets the common Latin case be settled by one tuple index,
  # without decoding either codepoint or stepping the machine. It is only sound
  # where the machine has no lookaheads, since a lookahead can report a position
  # other than the last accepting one; `nil` is returned in that case so the
  # caller can omit the fast path.
  def ascii_pair_breaks(data) do
    if uses_lookaheads?(data) do
      nil
    else
      for first <- 0..0x7F, second <- 0..0x7F do
        breaks_after_first?(data, first, second)
      end
      |> List.to_tuple()
    end
  end

  defp breaks_after_first?(data, first, second) do
    with next_state when is_integer(next_state) <-
           transition(data, data.start_state, symbol_for(data, first)),
         {:yes, _lookahead, _break_type} <- elem(data.states, next_state) do
      transition(data, next_state, symbol_for(data, second)) == nil
    else
      _other -> false
    end
  end

  defp symbol_for(data, codepoint) do
    Enum.find_value(Tuple.to_list(data.symbol_ranges), fn {from, to, symbol} ->
      codepoint >= from and codepoint <= to and symbol
    end)
  end

  @doc false
  def uses_lookaheads?(data) do
    data.states
    |> Tuple.to_list()
    |> Enum.any?(fn {accepting, lookahead, _break_type} ->
      lookahead != nil or match?({:lookahead, _}, accepting)
    end)
  end

  defp transition(_data, _state, nil), do: nil

  defp transition(data, state, symbol) do
    data.transitions |> elem(state) |> elem(symbol)
  end

  defp index_of(states, name) do
    Enum.find(states, fn state -> state.name == name end).index
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
