defmodule Unicode.String.Segment do
  @moduledoc """
  Implements the compilation of the Unicode
  segment rules.

  """

  import SweetXml
  require Unicode.Set

  @suppressions_variable "$Suppressions"

  # This is the formal definition but it takes a while to compile
  # and all of the known variable names are in the Latin-1 set
  # defguard is_id_start(char) when Unicode.Set.match?(char, "\\p{ID_start}")
  # defguard is_id_continue(char) when Unicode.Set.match?(char, "\\p{ID_continue}")

  @doc "Identifies if a codepoint is a valid start of an identifier"
  defguard is_id_start(char)
           when char in ?A..?Z

  @doc "Identifies if a codepoint is a valid identifier character"
  defguard is_id_continue(char)
           when char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char == ?_

  @doc "Returns a list of the locales known to `Unicode.String.Break`"
  def known_locales do
    locale_map()
    |> Map.keys()
  end

  @doc """
  Return the rules as defined by CLDR for a given
  locale and break type.

  """
  def rules(locale, segment_type, additional_variables \\ []) do
    with {:ok, segment} <- segments(locale, segment_type) do
      variables = Map.fetch!(segment, :variables) |> expand_variables(additional_variables)
      rules = Map.fetch!(segment, :rules)

      rules
      |> compile_rules(variables)
      |> wrap(:ok)
    end
  end

  @doc """
  Return the rules as defined by CLDR for a given
  locale and break type and raises on error.

  """
  def rules!(locale, segment_type, additional_variables \\ []) do
    case rules(locale, segment_type, additional_variables) do
      {:ok, rules} -> rules
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  def compile_rules(rules, variables) when is_list(rules) do
    rules
    |> expand_rules(variables)
    |> compile_rules
  end

  @doc """
  Compiles a segment rule in the context of a list
  of variables.

  The compile rule can then be inserted into a
  rule set.

  """
  def compile_rule(rule, variables) when is_map(rule) do
    compile_rules([rule], variables)
    |> hd
  end

  # These options set unicode mode. Interpreset certain
  # codes like \B and \w in the unicode space, ignore
  # unescaped whitespace in regexs
  @regex_options [:unicode, :extended, :ucp, :dollar_endonly, :dotall, :bsr_unicode]
  @rule_splitter ~r/[×÷]/u

  defp compile_rules(rules) do
    Enum.map(rules, fn {sequence, rule} ->
      [left, operator, right] = Regex.split(@rule_splitter, rule, include_captures: true)
      operator = if operator == "×", do: :no_break, else: :break

      left = if left != "", do: left <> "$", else: left
      right = if right != "", do: "^" <> right, else: right

      {sequence, {operator, compile_regex!(left), compile_regex!(right)}}
    end)
  end

  @doc false
  def suppressions_variable(locale, segment_type) do
    variable =
      locale
      |> suppressions!(segment_type)
      |> suppressions_regex

    if variable do
      %{name: @suppressions_variable, value: variable}
    else
      nil
    end
  end

  defp suppressions_regex([]) do
    nil
  end

  defp suppressions_regex(suppressions) do
    suppression_regex = Enum.map_join(suppressions, "|", &String.replace(&1, ".", "\\."))

    "(" <> suppression_regex <> ")"
  end

  @doc """
  Returns a list of the suppressions for a given
  locale and segment type.

  """
  def suppressions(locale, segment_type) do
    with {:ok, segment} <- segments(locale, segment_type) do
      {:ok, Map.get(segment, :suppressions, [])}
    end
  end

  @doc """
  Returns a list of the suppressions for a given
  locale and segment type and raises on error.

  """
  def suppressions!(locale, segment_type) do
    case suppressions(locale, segment_type) do
      {:ok, suppressions} -> suppressions
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  defp compile_regex!("") do
    :any
  end

  defp compile_regex!(string) do
    string
    |> String.trim()
    |> Unicode.Regex.compile!(@regex_options)
  end

  @doc """
  Evaluates a list of rules against a given
  string.

  """
  def evaluate_rules(string, rules) when is_binary(string) do
    evaluate_rules({"", string}, rules)
  end

  def evaluate_rules({string_before, string_after}, rules) do
    Enum.reduce_while(rules, [], fn rule, _acc ->
      {_sequence, {operator, _fore, _aft}} = rule

      case evaluate_rule({string_before, string_after}, rule) do
        {:pass, result} -> {:halt, {:pass, operator, result}}
        {:fail, string} -> {:cont, {:fail, string}}
      end
    end)
    |> return_break_or_no_break
  end

  # The final implicit rule is to
  # to break. ie: :any ÷ :any
  defp return_break_or_no_break({:fail, {before_string, ""}}) do
    {:break, {before_string, {"", ""}}}
  end

  defp return_break_or_no_break({:fail, {before_string, after_string}}) do
    <<char::utf8, rest::binary>> = after_string
    {:break, {before_string, {<<char::utf8>>, rest}}}
  end

  defp return_break_or_no_break({:pass, operator, result}) do
    {operator, result}
  end

  @split_options [parts: 2, include_captures: true, trim: true]

  # Process an `:any op regex` rule at end of string
  defp evaluate_rule({string_before, <<_::utf8>> = string_after}, {_seq, {_operator, :any, aft}}) do
    if Regex.match?(aft, string_after) do
      {:pass, {string_before, {string_after, ""}}}
    else
      {:fail, {string_before, string_after}}
    end
  end

  defp evaluate_rule({string_before, string_after}, {_seq, {_operator, :any, aft}}) do
    case Regex.split(aft, string_after, @split_options) do
      [match, rest] -> {:pass, {string_before, {match, rest}}}
      _other -> {:fail, {string_before, string_after}}
    end
  end

  # :any matches end of string
  defp evaluate_rule({string_before, "" = string_after}, {_seq, {_operator, fore, :any}}) do
    if Regex.match?(fore, string_before) do
      {:pass, {string_before, {"", ""}}}
    else
      {:fail, {string_before, string_after}}
    end
  end

  defp evaluate_rule({string_before, string_after}, {_seq, {_operator, fore, :any}}) do
    if Regex.match?(fore, string_before) do
      <<char::utf8, rest::binary>> = string_after
      {:pass, {string_before, {<<char::utf8>>, rest}}}
    else
      {:fail, {string_before, string_after}}
    end
  end

  defp evaluate_rule({string_before, string_after}, {_seq, {_operator, fore, aft}}) do
    if Regex.match?(fore, string_before) && Regex.match?(aft, string_after) do
      case Regex.split(aft, string_after, @split_options) do
        [match, rest] -> {:pass, {string_before, {match, rest}}}
        [match] -> {:pass, {string_before, {match, ""}}}
      end
    else
      {:fail, {string_before, string_after}}
    end
  end

  defp expand_rules(rules, variables) do
    Enum.reduce(rules, [], fn %{id: sequence, value: rule}, acc ->
      rule =
        rule
        |> String.trim()
        |> substitute_variables(variables)

      [{sequence, rule} | acc]
    end)
    |> Enum.sort()
  end

  def expand_variables(variables, additional_variables)
      when is_list(variables) and is_list(additional_variables) do
    Enum.reduce(variables ++ additional_variables, %{}, fn
      %{name: <<"$", name::binary>>, value: value}, variables ->
        new_value = substitute_variables(value, variables)
        Map.put(variables, name, new_value)
    end)
  end

  defp substitute_variables("", _variables) do
    ""
  end

  defp substitute_variables(<<"$", char::utf8, rest::binary>>, variables)
       when is_id_start(char) do
    {name, rest} = extract_variable_name(<<char::utf8>> <> rest)
    Map.fetch!(variables, name) <> substitute_variables(rest, variables)
  end

  defp substitute_variables(<<char::binary-1, rest::binary>>, variables) do
    char <> substitute_variables(rest, variables)
  end

  defp extract_variable_name("" = string) do
    {string, ""}
  end

  defp extract_variable_name(<<char::utf8, rest::binary>>)
       when is_id_continue(char) do
    {string, rest} = extract_variable_name(rest)
    {<<char::utf8>> <> string, rest}
  end

  defp extract_variable_name(rest) do
    {"", rest}
  end

  @app_name Mix.Project.config()[:app]

  @doctype "<!DOCTYPE ldml SYSTEM \"../../common/dtd/ldml.dtd\">"

  @doc false
  def segments_dir do
    Path.join(:code.priv_dir(@app_name), "/segments")
  end

  @doc false
  def locale_map do
    segments_dir()
    |> File.ls!()
    |> Enum.map(fn locale_file ->
      locale =
        locale_file
        |> String.split(".xml")
        |> hd
        |> String.replace("_", "-")

      {locale, locale_file}
    end)
    |> Map.new()
  end

  @doc """
  Returns a list of the ancestor locales
  of the a given locale.

  The list includes the given locale.

  """
  def ancestors(locale_name) do
    if Map.get(locale_map(), locale_name) do
      case String.split(locale_name, "-") do
        [locale] -> [locale, "root"]
        [locale, _territory] -> [locale_name, locale, "root"]
        [locale, script, _territory] -> [locale_name, "#{locale}-#{script}", locale, "root"]
      end
      |> wrap(:ok)
    else
      {:error, unknown_locale_error(locale_name)}
    end
  end

  @doc false
  def merge_ancestors("root") do
    raw_segments!("root")
    |> wrap(:ok)
  end

  def merge_ancestors(locale) when is_binary(locale) do
    with {:ok, ancestors} <- ancestors(locale) do
      merge_ancestors(ancestors)
      |> wrap(:ok)
    end
  end

  @doc false
  def merge_ancestors([locale, root]) do
    merge_ancestor(locale, raw_segments!(root))
  end

  def merge_ancestors([locale | rest]) do
    merge_ancestor(locale, merge_ancestors(rest))
  end

  # For each segment type, add the variables, rules and
  # suppressions from locale to other
  defp merge_ancestor(locale, other) do
    locale_segments = raw_segments!(locale)

    Enum.map(other, fn {segment_type, content} ->
      variables =
        Map.fetch!(content, :variables) ++
          (get_in(locale_segments, [segment_type, :variables]) || [])

      rules =
        Map.fetch!(content, :rules) ++
          (get_in(locale_segments, [segment_type, :rules]) || [])

      suppressions =
        Map.fetch!(content, :suppressions) ++
          (get_in(locale_segments, [segment_type, :suppressions]) || [])

      {segment_type, %{content | variables: variables, rules: rules, suppressions: suppressions}}
    end)
    |> Map.new()
  end

  defp raw_segments(locale) do
    if file = Map.get(locale_map(), locale) do
      content =
        segments_dir()
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
            id: ~x"./@id"f,
            value: ~x"./text()"s
          ],
          suppressions: ~x".//suppression/text()"ls
        )

      Enum.map(content, fn c ->
        type =
          c.type
          |> Macro.underscore()
          |> String.replace("__", "_")
          |> String.to_atom()

        {type, %{rules: c.rules, variables: c.variables, suppressions: c.suppressions}}
      end)
      |> Map.new()
      |> wrap(:ok)
    else
      {:error, unknown_locale_error(locale)}
    end
  end

  defp raw_segments!(locale) do
    case raw_segments(locale) do
      {:ok, segments} -> segments
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc false
  def segments(locale) do
    merge_ancestors(locale)
  end

  @doc false
  def segments(locale, segment_type) when is_binary(locale) do
    with {:ok, segments} <- segments(locale) do
      if segment = Map.get(segments, segment_type) do
        {:ok, segment}
      else
        {:error, unknown_segment_type_error(segment_type)}
      end
    end
  end

  defp wrap(term, atom) do
    {atom, term}
  end

  @doc false
  def unknown_locale_error(locale) do
    "Unknown locale #{inspect(locale)}"
  end

  @doc false
  def unknown_segment_type_error(segment_type) do
    "Unknown segment type #{inspect(segment_type)}"
  end
end
