defmodule Unicode.String.DictionaryBreak do
  @moduledoc """
  Implements ICU's lookahead-based dictionary word break algorithm
  for scripts that don't use spaces between words.

  This module handles word segmentation for Thai, Lao, Khmer, and
  Burmese (Myanmar) using the same approach as ICU's
  `DictionaryBreakEngine`: a 3-word lookahead with fallback for
  non-dictionary character sequences.

  The algorithm works by:

  1. At each position, gathering all dictionary word candidates
     (shortest to longest match).

  2. When exactly one candidate exists, accepting it immediately.

  3. When multiple candidates exist, using a 3-word lookahead to
     select the candidate that leads to the best overall
     segmentation — preferring the candidate where subsequent
     words are also found in the dictionary.

  4. When no dictionary word follows a short word, scanning
     forward through non-dictionary characters until finding a
     position where dictionary words resume, then combining the
     non-dictionary stretch with the preceding word.

  5. Absorbing combining marks (Unicode General Category M) into
     the preceding word so that vowel signs, tone marks, and
     virama/coeng characters stay attached to their base.

  """

  alias Unicode.String.Dictionary

  @root_combine_threshold 3
  @prefix_combine_threshold 3
  @min_word_span 4

  # ── Script-specific character sets ──────────────────────────

  # Characters that can begin a word
  @thai_begin_word_chars Enum.to_list(0x0E01..0x0E2E) ++ Enum.to_list(0x0E40..0x0E44)
  @lao_begin_word_chars Enum.to_list(0x0E81..0x0EAE) ++ Enum.to_list(0x0EDC..0x0EDD) ++ Enum.to_list(0x0EC0..0x0EC4)
  @khmer_begin_word_chars Enum.to_list(0x1780..0x17B3)
  @burmese_begin_word_chars Enum.to_list(0x1000..0x102A)

  # Characters that can end a word (used to detect plausible
  # word boundaries when scanning non-dictionary text).
  # Thai: all Thai SA characters minus above-vowels
  @thai_end_word_exclude [0x0E31 | Enum.to_list(0x0E40..0x0E44)]
  # Khmer: all Khmer SA characters minus coeng (U+17D2)
  @khmer_end_word_exclude [0x17D2]

  # Thai suffix characters
  @thai_paiyannoi 0x0E2F
  @thai_maiyamok 0x0E46

  # ── Public API ──────────────────────────────────────────────

  @doc """
  Splits a string into word segments using dictionary-based
  lookahead for the given locale.

  Returns a list of word segments (strings). Unlike the simple
  greedy algorithm, this considers multiple word candidates at
  each position and uses a 3-word lookahead to select the
  segmentation that produces the most dictionary-valid sequence.

  ### Arguments

  * `string` is a binary string to segment.

  * `locale` is a dictionary locale atom (`:th`, `:lo`, `:km`,
    or `:my`).

  ### Returns

  * A list of binary strings representing word segments.

  """
  @spec split(String.t(), atom()) :: [String.t()]
  def split("", _locale), do: []

  def split(string, locale) do
    codepoints = String.to_charlist(string)
    len = length(codepoints)

    if len < @min_word_span do
      [string]
    else
      {:ok, dict_locale} = Dictionary.dictionary_locale(locale)
      breaks = find_breaks(codepoints, 0, len, dict_locale, locale)
      extract_segments(string, breaks)
    end
  end

  @doc """
  Splits a string using the dictionary break algorithm for
  target-script ranges and a fallback function for other ranges.

  Text is partitioned into ranges belonging to the locale's
  script and ranges that don't. Dictionary breaking is applied
  to the former; `fallback_fn` is called on the latter.

  """
  @spec split_with_fallback(String.t(), atom(), (String.t() -> [String.t()])) :: [String.t()]
  def split_with_fallback("", _locale, _fallback_fn), do: []

  def split_with_fallback(string, locale, fallback_fn) do
    script_range = script_range_for(locale)
    {:ok, dict_locale} = Dictionary.dictionary_locale(locale)
    ranges = partition_by_script(string, script_range)

    Enum.flat_map(ranges, fn {type, segment} ->
      case type do
        :dict ->
          codepoints = String.to_charlist(segment)
          len = length(codepoints)

          if len < @min_word_span do
            [segment]
          else
            breaks = find_breaks(codepoints, 0, len, dict_locale, locale)
            extract_segments(segment, breaks)
          end

        :other ->
          fallback_fn.(segment)
      end
    end)
  end

  # Unicode script ranges for dictionary locales.
  defp script_range_for(:th), do: 0x0E01..0x0E5B
  defp script_range_for(:lo), do: 0x0E81..0x0EDF
  defp script_range_for(:km), do: 0x1780..0x17FF
  defp script_range_for(:my), do: 0x1000..0x109F
  defp script_range_for(_), do: 0..0

  # Partition a string into consecutive runs of target-script
  # characters and non-target-script characters.
  defp partition_by_script(string, script_range) do
    string
    |> String.to_charlist()
    |> Enum.chunk_while(
      {:init, []},
      fn cp, {prev_type, acc} ->
        type = if cp in script_range, do: :dict, else: :other

        case prev_type do
          :init ->
            {:cont, {type, [cp]}}

          ^type ->
            {:cont, {type, [cp | acc]}}

          _ ->
            segment = acc |> Enum.reverse() |> List.to_string()
            {:cont, {prev_type, segment}, {type, [cp]}}
        end
      end,
      fn
        {:init, []} ->
          {:cont, []}

        {type, acc} ->
          segment = acc |> Enum.reverse() |> List.to_string()
          {:cont, {type, segment}, []}
      end
    )
  end

  # ── Core algorithm ──────────────────────────────────────────

  # Find all word break positions in the codepoint list.
  defp find_breaks(codepoints, pos, range_end, dict_locale, locale) do
    find_breaks(codepoints, pos, range_end, dict_locale, locale, 0, [])
  end

  defp find_breaks(_codepoints, pos, range_end, _dict_locale, _locale, _words_found, breaks)
       when pos >= range_end do
    # Remove any break at the very end (it's implicit)
    breaks
    |> Enum.reverse()
    |> Enum.reject(&(&1 >= range_end))
  end

  defp find_breaks(codepoints, pos, range_end, dict_locale, locale, words_found, breaks) do
    # Gather all dictionary word candidates at this position
    candidates = dictionary_candidates(codepoints, pos, range_end, dict_locale)

    {word_len, words_found} =
      case candidates do
        [] ->
          # No dictionary word here
          {0, words_found}

        [single] ->
          # Exactly one candidate — accept it
          {single, words_found + 1}

        multiple ->
          # Multiple candidates — use lookahead to pick the best
          best = lookahead_select(codepoints, pos, range_end, dict_locale, multiple)
          {best, words_found + 1}
      end

    # Handle non-dictionary characters after a short or absent word
    word_len =
      if pos + word_len < range_end and word_len < @root_combine_threshold do
        next_candidates = dictionary_candidates(codepoints, pos + word_len, range_end, dict_locale)
        longest_prefix = longest_dictionary_prefix(codepoints, pos + word_len, range_end, dict_locale)

        if next_candidates == [] and (word_len == 0 or longest_prefix < @prefix_combine_threshold) do
          # Scan forward to find where dictionary words resume
          extra = scan_to_resync(codepoints, pos + word_len, range_end, dict_locale, locale)
          word_len + extra
        else
          word_len
        end
      else
        word_len
      end

    # Absorb combining marks
    word_len = absorb_marks(codepoints, pos + word_len, range_end) - pos
    # Absorb Thai suffix characters if applicable
    word_len = maybe_absorb_suffix(codepoints, pos, word_len, range_end, dict_locale, locale)

    # Record break position if we have a word
    if word_len > 0 do
      break_pos = pos + word_len
      find_breaks(codepoints, break_pos, range_end, dict_locale, locale, words_found, [break_pos | breaks])
    else
      # Skip one codepoint and try again (shouldn't happen with
      # proper resync, but a safety fallback)
      find_breaks(codepoints, pos + 1, range_end, dict_locale, locale, words_found, breaks)
    end
  end

  # ── Dictionary candidate gathering ─────────────────────────

  # Returns a sorted list of word lengths (in codepoints) that
  # are valid dictionary words starting at `pos`.
  defp dictionary_candidates(codepoints, pos, range_end, dict_locale) do
    gather_candidates(codepoints, pos, pos + 1, range_end, dict_locale, [])
  end

  defp gather_candidates(_codepoints, _start, current, range_end, _dict_locale, acc)
       when current > range_end do
    Enum.sort(acc)
  end

  defp gather_candidates(codepoints, start, current, range_end, dict_locale, acc) do
    word = codepoints_to_string(codepoints, start, current)

    case Dictionary.find_prefix(word, dict_locale) do
      {:ok, _} ->
        # Found a complete word — record its length and keep looking
        # for longer matches
        word_len = current - start
        gather_candidates(codepoints, start, current + 1, range_end, dict_locale, [word_len | acc])

      :prefix ->
        # Prefix match — keep extending
        gather_candidates(codepoints, start, current + 1, range_end, dict_locale, acc)

      :error ->
        # No match and no prefix — stop looking
        Enum.sort(acc)
    end
  end

  # ── 3-word lookahead ────────────────────────────────────────

  # Given multiple candidate word lengths at `pos`, try each
  # candidate and look ahead up to 2 more words to find the
  # candidate that leads to the best segmentation.
  defp lookahead_select(codepoints, pos, range_end, dict_locale, candidates) do
    # Try candidates from longest to shortest (ICU order)
    result =
      candidates
      |> Enum.reverse()
      |> Enum.reduce_while(nil, fn candidate_len, _acc ->
        next_pos = pos + candidate_len

        if next_pos >= range_end do
          # This candidate reaches the end — accept it
          {:halt, candidate_len}
        else
          # Look for word 2 at the position after this candidate
          word2_candidates = dictionary_candidates(codepoints, next_pos, range_end, dict_locale)

          if word2_candidates != [] do
            # Word 2 exists — try to confirm with word 3
            confirmed = try_word3(codepoints, next_pos, range_end, dict_locale, word2_candidates)

            if confirmed do
              {:halt, candidate_len}
            else
              # Word 2 existed but no word 3 confirmed it.
              # Mark this as best-so-far but keep trying shorter candidates.
              {:cont, candidate_len}
            end
          else
            # No word 2 — try next shorter candidate
            {:cont, nil}
          end
        end
      end)

    # If no candidate worked via lookahead, take the longest
    result || List.last(candidates)
  end

  # Try to find a word 3 for any of the word 2 candidates
  defp try_word3(codepoints, word1_end, range_end, dict_locale, word2_candidates) do
    Enum.any?(word2_candidates, fn w2_len ->
      word2_end = word1_end + w2_len

      if word2_end >= range_end do
        true
      else
        word3_candidates = dictionary_candidates(codepoints, word2_end, range_end, dict_locale)
        word3_candidates != []
      end
    end)
  end

  # ── Non-dictionary character scanning ───────────────────────

  # Scan forward from `pos` through non-dictionary characters
  # until finding a position where dictionary words resume.
  # Returns the number of codepoints consumed.
  defp scan_to_resync(codepoints, pos, range_end, dict_locale, locale) do
    scan_to_resync(codepoints, pos, pos, range_end, dict_locale, locale)
  end

  defp scan_to_resync(_codepoints, start, current, range_end, _dict_locale, _locale)
       when current >= range_end do
    current - start
  end

  defp scan_to_resync(codepoints, start, current, range_end, dict_locale, locale) do
    # Check if we're at a plausible word boundary:
    # previous char can end a word AND current char can begin a word
    if current > start do
      prev_cp = Enum.at(codepoints, current - 1)
      curr_cp = Enum.at(codepoints, current)

      if can_end_word?(prev_cp, locale) and can_begin_word?(curr_cp, locale) do
        # Check if a dictionary word starts here
        candidates = dictionary_candidates(codepoints, current, range_end, dict_locale)

        if candidates != [] do
          # Found a resync point — return characters consumed
          current - start
        else
          scan_to_resync(codepoints, start, current + 1, range_end, dict_locale, locale)
        end
      else
        scan_to_resync(codepoints, start, current + 1, range_end, dict_locale, locale)
      end
    else
      scan_to_resync(codepoints, start, current + 1, range_end, dict_locale, locale)
    end
  end

  # ── Combining mark absorption ───────────────────────────────

  # Advance past any combining marks (General Category M) at
  # the given position.
  defp absorb_marks(_codepoints, pos, range_end) when pos >= range_end, do: pos

  defp absorb_marks(codepoints, pos, range_end) do
    cp = Enum.at(codepoints, pos)

    if combining_mark?(cp) do
      absorb_marks(codepoints, pos + 1, range_end)
    else
      pos
    end
  end

  defp combining_mark?(codepoint) do
    Unicode.category(codepoint) in [:Mn, :Mc, :Me]
  end

  # ── Thai suffix absorption ──────────────────────────────────

  defp maybe_absorb_suffix(codepoints, pos, word_len, range_end, :th, _locale)
       when word_len > 0 and pos + word_len < range_end do
    next_pos = pos + word_len
    next_cp = Enum.at(codepoints, next_pos)

    # Only absorb suffix if no dictionary word follows
    candidates = dictionary_candidates(codepoints, next_pos, range_end, :th)

    if candidates == [] do
      cond do
        next_cp == @thai_paiyannoi ->
          # PAIYANNOI — absorb unless preceded by another suffix
          prev_cp = Enum.at(codepoints, next_pos - 1)

          if prev_cp not in [@thai_paiyannoi, @thai_maiyamok] do
            word_len + 1
          else
            word_len
          end

        next_cp == @thai_maiyamok ->
          # MAIYAMOK — absorb unless preceded by another MAIYAMOK
          prev_cp = Enum.at(codepoints, next_pos - 1)

          if prev_cp != @thai_maiyamok do
            word_len + 1
          else
            word_len
          end

        true ->
          word_len
      end
    else
      word_len
    end
  end

  defp maybe_absorb_suffix(_codepoints, _pos, word_len, _range_end, _dict_locale, _locale) do
    word_len
  end

  # ── Script-specific character set checks ────────────────────

  defp can_begin_word?(nil, _locale), do: false
  defp can_begin_word?(cp, :th), do: cp in @thai_begin_word_chars
  defp can_begin_word?(cp, :lo), do: cp in @lao_begin_word_chars
  defp can_begin_word?(cp, :km), do: cp in @khmer_begin_word_chars
  defp can_begin_word?(cp, :my), do: cp in @burmese_begin_word_chars
  defp can_begin_word?(_cp, _locale), do: false

  defp can_end_word?(nil, _locale), do: false

  defp can_end_word?(cp, :th) do
    cp in 0x0E01..0x0E3A and cp not in @thai_end_word_exclude
  end

  defp can_end_word?(cp, :lo) do
    cp in 0x0E81..0x0EDF and cp not in Enum.to_list(0x0EC0..0x0EC4)
  end

  defp can_end_word?(cp, :km) do
    cp in 0x1780..0x17FF and cp not in @khmer_end_word_exclude
  end

  defp can_end_word?(cp, :my) do
    cp in 0x1000..0x109F
  end

  defp can_end_word?(_cp, _locale), do: false

  # ── Utility functions ───────────────────────────────────────

  # Extract a substring from codepoints as a binary string.
  defp codepoints_to_string(codepoints, start, stop) do
    codepoints
    |> Enum.slice(start, stop - start)
    |> List.to_string()
  end

  # Find the length of the longest dictionary prefix at `pos`.
  defp longest_dictionary_prefix(codepoints, pos, range_end, dict_locale) do
    find_longest_prefix(codepoints, pos, pos + 1, range_end, dict_locale, 0)
  end

  defp find_longest_prefix(_codepoints, _start, current, range_end, _dict_locale, longest)
       when current > range_end do
    longest
  end

  defp find_longest_prefix(codepoints, start, current, range_end, dict_locale, longest) do
    word = codepoints_to_string(codepoints, start, current)

    case Dictionary.find_prefix(word, dict_locale) do
      {:ok, _} ->
        find_longest_prefix(codepoints, start, current + 1, range_end, dict_locale, current - start)

      :prefix ->
        find_longest_prefix(codepoints, start, current + 1, range_end, dict_locale, longest)

      :error ->
        longest
    end
  end

  # Convert a list of codepoint-based break positions into
  # string segments.
  defp extract_segments(string, []) do
    if string == "", do: [], else: [string]
  end

  defp extract_segments(string, breaks) do
    codepoints = String.to_charlist(string)
    do_extract(codepoints, [0 | breaks] ++ [length(codepoints)])
  end

  defp do_extract(_codepoints, [_last]) do
    []
  end

  defp do_extract(codepoints, [start, stop | rest]) do
    segment = codepoints_to_string(codepoints, start, stop)

    if segment == "" do
      do_extract(codepoints, [stop | rest])
    else
      [segment | do_extract(codepoints, [stop | rest])]
    end
  end
end
