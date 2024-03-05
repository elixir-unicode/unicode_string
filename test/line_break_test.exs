defmodule Unicode.String.LineBreak.Test do
  use ExUnit.Case, async: true

  test "Unicode.String.split that end in a quote mark" do
    assert ["He ", "said, ", "\"A ", "cup ", "of ", "hot ", "tea?\""] =
      Unicode.String.split(~s(He said, "A cup of hot tea?"), locale: :en, break: :line)
  end

  test "Unicode.String.next that ends in a quote mark" do
    assert Unicode.String.next(~s(tea"), locale: :en, break: :line) ==
      {"tea\"", ""}
  end
end