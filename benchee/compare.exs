s1 = "ABC"
s2 = "abc"

Benchee.run(%{
  "Unicode.String.equal_ignore_case?"  =>
    fn -> Unicode.String.equals_ignore_case?(s1, s2) end,
  "String.==" =>
    fn -> s1 == s2 end,
})