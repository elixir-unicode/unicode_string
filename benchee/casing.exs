s = "THIS IS A STRING WE ARE GOING TO DOWNCASE WITH CHARACTERS THAT HAVE MAPPING AND THOSE THAT DONT 1234^&*&^%$)(*)}"

Benchee.run(%{
  "Unicode.String.Case.Mapping.upcase"  =>
    fn -> Unicode.String.Case.Mapping.downcase(s) end,
})
