defmodule Unicode.String.Segment do
  @moduledoc """
  Implements the compilation of the Unicode
  segment rules.

  """

  import SweetXml

  @root_locale "root"
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

  @doc """
  Returns the segmentation rules defined by CLDR for a locale and break type.

  ### Arguments

  * `locale` is any locale returned by `known_segmentation_locales/0`.

  * `segment_type` is one of `:grapheme_cluster_break`, `:word_break`,
    `:sentence_break` or `:line_break`.

  * `additional_variables` is a keyword list of variable definitions merged over
    the ones CLDR defines for the locale. The default is `[]`.

  ### Returns

  * `{:ok, rules}` where `rules` is a list of `{sequence, {operator, before, after}}`
    tuples ordered by rule sequence number.

  * `{:error, reason}` if the locale or segment type is unknown.

  ### Examples

      iex> {:ok, rules} = Unicode.String.Segment.rules(:en, :sentence_break)
      iex> is_list(rules) and rules != []
      true

      iex> Unicode.String.Segment.rules(:xx, :sentence_break)
      {:error, "Unknown locale \\"xx\\""}

  """
  def rules(locale, segment_type, additional_variables \\ []) do
    with {:ok, segment} <- segments(locale, segment_type) do
      variables = Map.fetch!(segment, :variables) |> expand_variables(additional_variables)
      rules = Map.fetch!(segment, :rules)

      rules
      |> compile_rules(variables, [])
      |> wrap(:ok)
    end
  end

  @doc """
  Returns the segmentation rules for a locale and break type, raising on error.

  ### Arguments

  * `locale` is any locale returned by `known_segmentation_locales/0`.

  * `segment_type` is one of `:grapheme_cluster_break`, `:word_break`,
    `:sentence_break` or `:line_break`.

  * `additional_variables` is a keyword list of variable definitions merged over
    the ones CLDR defines for the locale. The default is `[]`.

  ### Returns

  * A list of `{sequence, {operator, before, after}}` tuples.

  * Raises `Unicode.String.Segment.SegmentError` if the locale or segment type
    is unknown.

  ### Examples

      iex> rules = Unicode.String.Segment.rules!(:en, :sentence_break)
      iex> is_list(rules) and rules != []
      true

  """
  def rules!(locale, segment_type, additional_variables \\ []) do
    case rules(locale, segment_type, additional_variables) do
      {:ok, rules} -> rules
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  def compile_rules(rules, variables, regex_options) when is_list(rules) do
    rules
    |> expand_rules(variables)
    |> compile_rules(regex_options)
  end

  # These options set unicode mode. Interpret certain
  # codes like \B and \w in the unicode space, ignore
  # unescaped whitespace in regexs
  @regex_options [:unicode, :extended, :ucp, :dollar_endonly, :dotall, :bsr_unicode]
  @rule_splitter "[×÷]"

  defp compile_rules(rules, regex_options) do
    Enum.map(rules, fn {sequence, rule} ->
      [left, operator, right] = Regex.split(~r/#{@rule_splitter}/u, rule, include_captures: true)
      operator = if operator == "×", do: :no_break, else: :break

      left = if left != "", do: left <> "$", else: left
      right = if right != "", do: "^" <> right, else: right

      {sequence,
       {operator, expand_regex(left, regex_options), expand_regex(right, regex_options)}}
    end)
  end

  @doc """
  Compiles one segmentation rule against a set of variable definitions.

  The compiled rule can then be inserted into a rule set and evaluated with
  `evaluate_rules/2`.

  ### Arguments

  * `rule` is a map with an `:id` (the rule's sequence number) and a `:value`
    (the rule source, in which `×` means *no break here* and `÷` means *break
    here*).

  * `variables` is the list of variable definitions that `$Name` references in
    the rule are expanded against.

  * `regex_options` is a list of options passed to `Regex.compile/2`. The
    default is `[]`.

  ### Returns

  * `{sequence, {operator, before, after}}` where `operator` is `:break` or
    `:no_break` and `before` and `after` are compiled regular expressions.

  ### Examples

      iex> {3.0, {operator, _before, _after}} =
      ...>   Unicode.String.Segment.compile_rule(%{id: 3.0, value: "a × b"}, [])
      iex> operator
      :no_break

  """
  def compile_rule(rule, variables, regex_options \\ []) when is_map(rule) do
    compile_rules([rule], variables, regex_options)
    |> hd
  end

  @doc false
  def suppressions_variable(locale, segment_type) do
    variable =
      locale
      |> suppressions!(segment_type)
      |> suppressions_regex()

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
  Returns the abbreviation suppressions CLDR defines for a locale and segment type.

  A suppression is an abbreviation such as "Mr." that ends in a full stop
  without ending a sentence.

  ### Arguments

  * `locale` is any locale returned by `known_segmentation_locales/0`.

  * `segment_type` is one of `:grapheme_cluster_break`, `:word_break`,
    `:sentence_break` or `:line_break`. Only `:sentence_break` has suppressions.

  ### Returns

  * `{:ok, suppressions}` where `suppressions` is a list of strings.

  * `{:error, reason}` if the locale or segment type is unknown.

  ### Examples

      iex> {:ok, suppressions} = Unicode.String.Segment.suppressions(:en, :sentence_break)
      iex> "Alt." in suppressions
      true

      iex> Unicode.String.Segment.suppressions(:xx, :sentence_break)
      {:error, "Unknown locale \\"xx\\""}

  """
  def suppressions(locale, segment_type) do
    with {:ok, segment} <- segments(locale, segment_type) do
      {:ok, Map.get(segment, :suppressions, [])}
    end
  end

  @doc """
  Returns the abbreviation suppressions for a locale and segment type, raising
  on error.

  ### Arguments

  * `locale` is any locale returned by `known_segmentation_locales/0`.

  * `segment_type` is one of `:grapheme_cluster_break`, `:word_break`,
    `:sentence_break` or `:line_break`. Only `:sentence_break` has suppressions.

  ### Returns

  * A list of abbreviation strings.

  * Raises `Unicode.String.Segment.SegmentError` if the locale or segment type
    is unknown.

  ### Examples

      iex> suppressions = Unicode.String.Segment.suppressions!(:en, :sentence_break)
      iex> "Alt." in suppressions
      true

  """
  def suppressions!(locale, segment_type) do
    case suppressions(locale, segment_type) do
      {:ok, suppressions} -> suppressions
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  defp expand_regex("", _regex_options) do
    :any
  end

  # Delete spaces because PCRE doesn't ignore them

  defp expand_regex(string, regex_options) do
    string
    |> String.trim()
    |> String.replace(" ", "")
    |> Unicode.Regex.expand_regex(@regex_options ++ regex_options)
  end

  @doc """
  Evaluates a compiled rule set at one position in a string.

  Rules are tried in sequence order and the first one that matches decides the
  position, which is how the ordered rule lists of UAX #14 and UAX #29 are
  defined to work.

  ### Arguments

  * `string` is either a string, in which case the position tested is its start,
    or a `{string_before, string_after}` tuple naming the position between them.

  * `rules` is a compiled rule set as returned by `rules/3`.

  ### Returns

  * `{:break, {string_before, {matched, rest}}}` when a break is permitted at
    the position.

  * `{:no_break, {string_before, {matched, rest}}}` when it is not.

  ### Examples

      iex> {:ok, rules} = Unicode.String.Segment.rules(:en, :sentence_break)
      iex> {operator, _match} = Unicode.String.Segment.evaluate_rules("Hello there.", rules)
      iex> operator
      :no_break

  """
  def evaluate_rules(string, rules) when is_binary(string) do
    evaluate_rules({"", string}, rules)
  end

  def evaluate_rules({string_before, string_after}, rules) do
    Enum.reduce_while(rules, [], fn rule, _acc ->
      {_rule_number, {operator, _fore, _aft}} = rule

      case evaluate_rule({string_before, string_after}, rule) do
        {:pass, result} ->
          {:halt, {:pass, operator, result}}

        {:fail, string} ->
          {:cont, {:fail, string}}
      end
    end)
    |> return_break_or_no_break
  end

  # The final implicit rule is to to break. ie: :any ÷ :any
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
  defp evaluate_rule(
         {string_before, <<_::utf8>> = string_after},
         {_seq, {_operator, :any, {aft, regex_options}}}
       ) do
    aft = Regex.compile!(aft, regex_options)

    if Regex.match?(aft, string_after) do
      {:pass, {string_before, {string_after, ""}}}
    else
      {:fail, {string_before, string_after}}
    end
  end

  defp evaluate_rule(
         {string_before, string_after},
         {_seq, {_operator, :any, {aft, regex_options}}}
       ) do
    aft = Regex.compile!(aft, regex_options)

    case Regex.split(aft, string_after, @split_options) do
      [match, rest] -> {:pass, {string_before, {match, rest}}}
      _other -> {:fail, {string_before, string_after}}
    end
  end

  # Ignore suppressions at end of the string
  defp evaluate_rule(
         {string_before, string_after},
         {10.5, {_operator, {fore, regex_options}, :any}}
       ) do
    fore = Regex.compile!(fore, regex_options)

    if Regex.match?(fore, string_before) do
      # IO.inspect {string_before, string_after}, label: "Matched Rule 10.5"
      case Regex.split(fore, string_before, @split_options) do
        [match] ->
          # IO.inspect {operator, match}, label: "Matched One"
          {:pass, {string_before, {match, ""}}}

        [match, rest] ->
          # IO.inspect {operator, match, rest}, label: "Matched"
          {:pass, {string_before, {match, rest}}}
      end
    else
      # IO.inspect {string_before, string_after}, label: "Did not match Rule 10.5"
      {:fail, {string_before, string_after}}
    end
  end

  # :any matches end of string
  defp evaluate_rule(
         {string_before, "" = string_after},
         {_seq, {_operator, {fore, regex_options}, :any}}
       ) do
    fore = Regex.compile!(fore, regex_options)

    if Regex.match?(fore, string_before) do
      {:pass, {string_before, {"", ""}}}
    else
      {:fail, {string_before, string_after}}
    end
  end

  defp evaluate_rule(
         {string_before, string_after},
         {_seq, {_operator, {fore, regex_options}, :any}}
       ) do
    fore = Regex.compile!(fore, regex_options)

    if Regex.match?(fore, string_before) do
      <<char::utf8, rest::binary>> = string_after
      {:pass, {string_before, {<<char::utf8>>, rest}}}
    else
      {:fail, {string_before, string_after}}
    end
  end

  defp evaluate_rule(
         {string_before, string_after},
         {_seq, {_operator, {fore, fore_regex_options}, {aft, aft_regex_options}}}
       ) do
    fore = Regex.compile!(fore, fore_regex_options)
    aft = Regex.compile!(aft, aft_regex_options)

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
  Returns the locales for which CLDR ships segmentation data.

  A locale not in this list falls back to `:root`, which carries the untailored
  UAX #14 and UAX #29 rules.

  ### Returns

  * A list of locale atoms.

  ### Examples

      iex> locales = Unicode.String.Segment.known_segmentation_locales()
      iex> :root in locales and :ja in locales
      true

  """
  def known_segmentation_locales do
    locale_map()
    |> Map.keys()
    |> Enum.map(&String.to_atom/1)
  end

  @doc """
  Returns a locale and its ancestors, most specific first.

  Segmentation data is merged along this chain, so a locale inherits everything
  its ancestors define and overrides only what it states itself.

  ### Arguments

  * `locale_name` is a locale *string* such as `"en-US"`. Note that this differs
    from `known_segmentation_locales/0`, which returns atoms.

  ### Returns

  * `{:ok, locales}` where `locales` is a list of locale strings beginning with
    `locale_name` and ending with `"root"`.

  * `{:error, reason}` if the locale is unknown.

  ### Examples

      iex> Unicode.String.Segment.ancestors("en-US")
      {:ok, ["en-US", "en", "root"]}

      iex> Unicode.String.Segment.ancestors("xx-YY")
      {:error, "Unknown locale \\"xx-YY\\""}

  """

  def ancestors(locale_name) do
    if Map.get(locale_map(), locale_name) do
      case String.split(locale_name, "-") do
        [locale] -> [locale, @root_locale]
        [locale, _territory] -> [locale_name, locale, @root_locale]
        [locale, script, _territory] -> [locale_name, "#{locale}-#{script}", locale, @root_locale]
      end
      |> wrap(:ok)
    else
      {:error, unknown_locale_error(locale_name)}
    end
  end

  @doc false
  def merge_ancestors(@root_locale) do
    raw_segments!(@root_locale)
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
  def segments(locale) when is_binary(locale) do
    merge_ancestors(locale)
  end

  def segments(locale) when is_atom(locale) do
    locale
    |> Atom.to_string()
    |> segments()
  end

  @doc false
  def segments(locale, segment_type) do
    with {:ok, segments} <- segments(to_string(locale)) do
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
