defmodule Unicode.String.Segments do
  import SweetXml

  @app_name Mix.Project.config[:app]
  @segments_dir Path.join(:code.priv_dir(@app_name), "/segments")
  @locales File.ls!(@segments_dir)

  @doctype "<!DOCTYPE ldml SYSTEM \"../../common/dtd/ldml.dtd\">"

  @locale_map Enum.map(@locales, fn locale_file ->
    locale =
      locale_file
      |> String.split(".xml")
      |> hd
      |> String.replace("_", "-")

    {locale, locale_file}
  end)
  |> Map.new

  @segments Enum.map(@locale_map, fn {locale, file} ->
    content =
      @segments_dir
      |> Path.join(file)
      |> File.read!()
      |> String.replace(@doctype, "")
      |> xpath(~x"//segmentation"l,
        type: ~x"./@type"s,
        variables: [
           ~x".//variable"l,
           name: ~x"./@id"s,
           value: ~x"./text()"s
        ],
        rules: [
          ~x".//rule"l,
           name: ~x"./@id"f,
           value: ~x"./text()"s
        ],
        supressions: ~x".//suppression/text()"ls
      )

    content = Enum.map(content, fn c ->
      type = c.type
      |> Macro.underscore()
      |> String.replace("__", "_")
      |> String.to_atom

      {type, %{rules: c.rules, variables: c.variables, supressions: c.supressions}}
    end)
    |> Map.new

    {locale, content}
  end)
  |> Map.new

  for {locale, _file} <- @locale_map do
    def segments(unquote(locale)) do
      unquote(Macro.escape(Map.get(@segments, locale)))
    end

    for segment_type <- Map.get(@segments, "root") |> Map.keys do
      def segments(unquote(locale), unquote(segment_type)) do
        unquote(locale)
        |> segments
        |> Map.get(unquote(segment_type))
      end
    end
  end

  def segments(locale) do
    {:error, "Unknown locale #{inspect locale}}"}
  end

  def segments(locale, segment_type) do
    {:error, "Unknown locale #{inspect locale} or segment type #{inspect segment_type}"}
  end
end