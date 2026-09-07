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

  describe "dictionary segmentation respects the rules at its edges" do
    # The rules bind punctuation to an adjacent word — LB14 forbids a break
    # after an opening bracket, LB13 forbids one before a closing bracket — so
    # the dictionary pass must not introduce one.
    test "an opening bracket stays attached to the following dictionary word" do
      assert ["(ทิว", "เขา", "แดน", "ลาว)"] =
               Unicode.String.split("(ทิวเขาแดนลาว)", locale: :en, break: :line)
    end

    test "split agrees with break? at the bracket boundaries" do
      text = "(ทิวเขาแดนลาว)"

      refute Unicode.String.break?({"(", "ทิวเขาแดนลาว)"}, locale: :en, break: :line)
      refute Unicode.String.break?({"(ทิวเขาแดนลาว", ")"}, locale: :en, break: :line)

      segments = Unicode.String.split(text, locale: :en, break: :line)
      assert Enum.join(segments) == text
      refute "(" in segments
      refute ")" in segments
    end

    test "the dictionary still breaks between characters of its own script" do
      assert ["ทิว", "เขา", "แดน", "ลาว"] =
               Unicode.String.split("ทิวเขาแดนลาว", locale: :en, break: :line)
    end
  end
end
