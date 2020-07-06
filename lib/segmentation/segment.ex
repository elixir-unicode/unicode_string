defmodule Unicode.String.Segment do
  @moduledoc false

  import SweetXml
  require Unicode.Set

  defguard is_id_start(char) when Unicode.Set.match?(char, "\\p{ID_start}")
  defguard is_id_continue(char) when Unicode.Set.match?(char, "\\p{ID_continue}")

  def rules(locale, segment_type) do
    with {:ok, segment} <- segments(locale, segment_type) do
      variables = Map.fetch!(segment, :variables) |> expand_variables()
      rules = Map.fetch!(segment, :rules)

      rules
      |> expand_rules(variables)
      |> compile_rules
      |> wrap(:ok)
    end
  end

  defp wrap(term, atom) do
    {atom, term}
  end

  # THese options set unicode mode. Interpreset certain
  # codes like \B and \w in the unicode space, ignore
  # unescaped whitespace in regexs
  @regex_options [:unicode, :anchored, :extended, :ucp]
  @rule_splitter ~r/[×÷]/u

  defp compile_rules(rules) do
    Enum.map(rules, fn {sequence, rule} ->
      [left, operator, right] = Regex.split(@rule_splitter, rule, include_captures: true)
      compiled_left = compile_regex(left)
      compiled_right = compile_regex(right)
      {sequence, {operator, compiled_left, compiled_right}}
    end)
  end

  defp compile_regex("") do
    :any
  end

  defp compile_regex(string) do
    string
    |> String.trim
    |> Unicode.Regex.compile!(@regex_options)
  end

  def test(string, locale, type) do
    with {:ok, rules} <- rules(locale, type) do
      Enum.each rules, fn
        {seq, {_op, :any, _a}} ->
          IO.inspect([string], label: inspect(seq))
        {seq, {_op, b, _a}} ->
          Regex.split(b, string, parts: 2, include_captures: true, trim: true)
          |> IO.inspect(label: inspect(seq))
      end
    end
  end

  def get_rule(rule, locale, type) when is_float(rule) do
    with {:ok, rules} <- rules(locale, type) do
      Enum.find(rules, &(elem(&1, 0) == rule))
    end
  end

  defp expand_rules(rules, variables) do
    Enum.reduce(rules, [], fn %{name: sequence, value: rule}, acc ->
      rule =
        rule
        |> String.trim
        |> substitute_variables(variables)

      [{sequence, rule} | acc]
    end)
    |> Enum.sort
  end

  defp expand_variables(variable_list) do
    Enum.reduce variable_list, %{}, fn
      %{name: << "$", name :: binary >>, value: value}, variables ->
        new_value = substitute_variables(value, variables)
        Map.put(variables, name, new_value)
    end
  end

  defp substitute_variables("", _variables) do
    ""
  end

  defp substitute_variables(<< "$", char :: utf8, rest :: binary >>, variables)
      when is_id_start(char) do
    {name, rest} = extract_variable_name(<< char >> <> rest)
    Map.fetch!(variables, name) <> substitute_variables(rest, variables)
  end

  defp substitute_variables(<< char :: binary-1, rest :: binary >>, variables) do
    char <> substitute_variables(rest, variables)
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
    defp segments(unquote(locale)) do
      {:ok, unquote(Macro.escape(Map.get(@segments, locale)))}
    end

    for segment_type <- Map.get(@segments, "root") |> Map.keys do
      defp segments(unquote(locale), unquote(segment_type)) do
        {:ok, segments} = segments(unquote(locale))
        Map.fetch(segments, unquote(segment_type))
      end
    end
  end

  defp segments(locale) do
    {:error, "Unknown locale #{inspect locale}}"}
  end

  defp segments(locale, segment_type) do
    {:error, "Unknown locale #{inspect locale} or segment type #{inspect segment_type}"}
  end
end