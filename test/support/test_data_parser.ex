defmodule Unicode.String.TestDataParser do

  @word_break "./test/support/test_data/WordBreakTest.txt"

  def codepoints("") do
    "<<>>"
  end

  def codepoints(string) do
    codepoints =
      string
      |> String.codepoints()
      |> Enum.map(fn codepoint ->
        <<codepoint::utf8>> = codepoint
        codepoint = Integer.to_string(codepoint, 16)
        "0x" <> pad(codepoint) <> codepoint <> "::utf8"
      end)

    "<<" <> Enum.join(codepoints, ", ") <> ">>"
  end

  defp pad(<<_::utf8, _::utf8, _::utf8, _::utf8, _::utf8>>), do: ""
  defp pad(<<_::utf8, _::utf8, _::utf8, _::utf8>>), do: ""
  defp pad(<<_::utf8, _::utf8, _::utf8>>), do: "0"
  defp pad(<<_::utf8, _::utf8,>>), do: "00"
  defp pad(<<_::utf8>>), do: "000"

  def tests(path \\ @word_break) do
    path
    |> parse()
    |> separate_tests()
  end

  def separate_tests(tests) do
    tests
    |> Enum.reduce({"", []}, &reduce_tests/2)
    |> elem(1)
    # |> Enum.uniq_by(fn {line, {break?, left, right} -> {line, break?, left, right} end)
    |> Enum.reverse()
  end

  defp reduce_tests({_index, [_eot]}, {_previous, acc}) do
    {"", acc}
  end

  defp reduce_tests({line, [{left, _}, {break?, _} | rest]}, {previous, acc}) do
    previous = previous <> left
    test = {line, break?, previous, collect(rest)}
    acc = [test | acc]

    reduce_tests({line, rest}, {previous, acc})
  end

  defp collect(rest) do
    Enum.reduce(rest, "", fn
      {char, _descr}, acc when is_binary(char) ->
        acc <> char
      _break?, acc ->
        acc
    end)
  end

  def parse(path \\ @word_break)

  def parse(path) when is_binary(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {string, _line} -> String.starts_with?(string, "#") || string == "" end)
    |> Enum.map(fn {string, line} -> {String.split(string, "#"), line} end)
    |> Enum.map(&parse/1)
    |> Enum.map(fn {line, rule, description} -> {line, Enum.zip(rule,description)} end)
  end

  def parse({[test, description], line}) do
    {line, parse_test(test), parse_description(description)}
  end

  defp parse_test(test) do
    test = String.trim(test)

    ~r/[÷×]/u
    |> Regex.split(test, include_captures: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_test_part/1)
  end

  defp parse_test_part(operator) when operator in ["÷", "×"] do
    String.to_atom(operator)
  end

  defp parse_test_part("") do
    ""
  end

  defp parse_test_part(codepoint) do
    codepoint
    |> String.to_integer(16)
    |> List.wrap()
    |> List.to_string()
  end
  # ÷ 0001 ÷ 0001 ÷	#  ÷ [0.2] <START OF HEADING> (Other) ÷ [999.0] <START OF HEADING> (Other) ÷ [0.3]

  defp parse_description(description) do
    description = String.trim(description)

    ~r/[÷×]/u
    |> Regex.split(description, include_captures: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_description_part/1)
  end

  def parse_description_part(operator) when operator in ["÷", "×"] do
    operator
  end

  def parse_description_part("") do
    {"0.0", "SOT"}
  end

  def parse_description_part(part) do
    case String.split(part, " ", parts: 2) do
      [rule_number, rule_description] ->
        part
        |> String.trim()
        |> String.split(" ", parts: 2)
        |> Enum.map(&String.trim/1)

        [_, rule_number, _] = String.split(rule_number, ["[", "]"])
        {rule_number, rule_description}

      [rule_number] ->
        [_, rule_number, _] = String.split(rule_number, ["[", "]"])
        {rule_number, "EOT"}
    end
  end
end