defmodule Unicode.String.IcuRbbiTest do
  use ExUnit.Case, async: true

  alias Unicode.String.IcuRbbiParser

  @rbbi_path "./test/support/test_data/icu_rbbitst.txt"

  # Sentence-break cases from ICU's rbbitst.txt where this project's
  # behaviour deliberately diverges from ICU. The 1-based index is the
  # position of the case within the sent-mode block list.
  @sentence_known_divergences %{
    3 => "ICU heuristic suppresses single-letter 'D.' less aggressively than CLDR's documented rule",
    4 => "ICU heuristic skips short suppressions like 'On.' in some contexts"
  }

  parsed = IcuRbbiParser.parse(@rbbi_path)
  sentence_blocks = Enum.filter(parsed, &(&1.mode == :sent))

  describe "ICU rbbitst.txt sentence break corpus" do
    for {block, idx} <- Enum.with_index(sentence_blocks, 1) do
      name =
        "case ##{idx} (locale=#{block.locale}, ss=#{block.suppressions?})"

      if Map.has_key?(@sentence_known_divergences, idx) do
        @tag skip: Map.fetch!(@sentence_known_divergences, idx)
        test name do
          :skipped
        end
      else
        test name do
          block = unquote(Macro.escape(block))

          actual =
            Unicode.String.split(block.input,
              break: :sentence,
              locale: block.locale,
              suppressions: block.suppressions?
            )

          assert actual == block.expected
        end
      end
    end
  end
end
