defmodule Unicode.String.Segments do
  @moduledoc false

  import SweetXml

  @app_name Mix.Project.config[:app]
  @segments_dir Path.join(:code.priv_dir(@app_name), "/segments")
  @locales File.ls!(@segments_dir)

  @doctype "<!DOCTYPE ldml SYSTEM \"../../common/dtd/ldml.dtd\">"

  require Unicode.Set
  defguard is_id_start(char) when Unicode.Set.match?(char, "\\p{ID_start}")
  defguard is_id_continue(char) when Unicode.Set.match?(char, "\\p{ID_continue}")

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

  def expand_variables(variable_list) do
    Enum.reduce variable_list, %{}, fn %{name: name, value: value}, variables ->
      new_value = substitute_variables(value, variables)
      Map.put(variables, name, new_value)
    end
  end

  def substitute_variables("", _variables) do
    ""
  end

  def substitute_variables(<< "$", char :: utf8, rest :: binary >>, variables)
      when is_id_start(char) do
    {name, rest} = extract_variable_name(<< char >> <> rest)
    Map.fetch!(variables, name) <> substitute_variables(rest, variables)
  end

  def substitute_variables(<< char :: binary-1, rest :: binary >>, variables) do
    << char, substitute_variables(rest, variables) >>
  end

  defp extract_variable_name("" = string) do
    {string, ""}
  end

  defp extract_variable_name(<< char :: utf8, rest :: binary >>)
       when is_id_continue(char) do
    {string, rest} = extract_variable_name(rest)
    {<< char >> <> string, rest}
  end

  defp extract_variable_name(rest) do
    {"", rest}
  end

end