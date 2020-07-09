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
      operator = if operator == "×", do: :no_break, else: :break
      {sequence, {operator, compile_regex!(left), compile_regex!(right)}}
    end)
  end

  defp compile_regex!("") do
    :any
  end

  defp compile_regex!(string) do
    string
    |> String.trim
    |> Unicode.Regex.compile!(@regex_options)
  end

  def evaluate_rules(string, rules) do
    Enum.reduce_while(rules, [], fn rule, _acc ->
      {_sequence, {operator, _fore, _aft}} = rule
      case evaluate_rule(string, rule) do
        {:pass, result} -> {:halt, {:pass, operator, result}}
        {:fail, result} -> {:cont, {:fail, operator, result}}
      end
    end)
    |> default_to_break
  end

  def default_to_break({:fail, _, string}) do
    << char :: utf8, rest :: binary >> = string
    {:break, [<< char >>, rest]}
  end

  def default_to_break({:pass, operator, result}) do
    {operator, result}
  end

  def evaluate_rule(string, {_seq, {_operator, :any, aft}}) do
    << char :: utf8, rest :: binary >> = string
    if Regex.match?(aft, rest) do
      {:pass, [<< char >>, rest]}
    else
      {:fail, string}
    end
  end

  def evaluate_rule(string, {_seq, {_operator, fore, :any}}) do
    case Regex.split(fore, string, parts: 2, include_captures: true, trim: true) do
      [match, rest] ->
        {:pass, [match, rest]}
      [_other] ->
        {:fail, string}
    end
  end

  def evaluate_rule(string, {_seq, {_operator, fore, aft}}) do
    case Regex.split(fore, string, parts: 2, include_captures: true, trim: true) do
      [match, rest] ->
        if Regex.match?(aft, rest), do: {:pass, [match, rest]}, else: {:fail, string}
      [_other] ->
        {:fail, string}
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