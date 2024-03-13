Benchee.run(%{
  "Unicode.String.Break.next/4"  =>
    fn -> Unicode.String.Break.next("test123 ", "root", :word, []) end,
})