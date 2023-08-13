s = "THIS IS A STRING WE ARE GOING TO DOWNCASE WITH CHARACTERS THAT HAVE MAPPING AND THOSE THAT DONT 1234^&*&^%$)(*)}"

Benchee.run(%{
  "Unicode.String.Case.Mapping.downcase"  =>
    fn -> Unicode.String.Case.Mapping.downcase(s) end,
  "String.downcase default mode"  =>
    fn -> String.downcase(s) end,
  "String.downcase ASCII mode"  =>
    fn -> String.downcase(s, :ascii) end,
})

