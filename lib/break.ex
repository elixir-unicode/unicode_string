defmodule Unicode.String.Break do
  @moduledoc """


  """
  for locale <- Unicode.String.Segment.locales do
    {:ok, segments} = Unicode.String.Segment.segments(locale)

    for segment_type <- Map.keys(segments) do
      def rules(unquote(locale), unquote(segment_type)) do
        unquote(Macro.escape(Unicode.String.Segment.rules(locale, segment_type)))
      end

      for suppression <- Unicode.String.Segment.suppressions!(locale, segment_type) do
        def suppress(<< unquote(suppression), rest :: binary >>, unquote(locale), unquote(segment_type)) do
          [unquote(suppression), rest]
        end
      end
    end
  end

  @default_locale "root"

  def rules(_other, segment_type) do
    Unicode.String.Segment.rules(@default_locale, segment_type)
  end

  def suppress(string, _other, _segment_type) do
    ["", string]
  end

end