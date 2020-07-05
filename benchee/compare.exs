s1 = "ABC"
s2 = "abc"

Benchee.run(%{
  "Unicode.String.equal_ignoring_case?"  =>
    fn -> Unicode.String.equals_ignoring_case?(s1, s2) end,
  "String.==" =>
    fn -> s1 == s2 end,
  "String.downcase compare" =>
    fn -> String.downcase(s1) == String.downcase(s2) end,
})