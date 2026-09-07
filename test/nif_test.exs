defmodule Unicode.String.NifTest do
  use ExUnit.Case, async: true

  alias Unicode.String.Nif

  # The NIF is opt-in, so these tests must pass whether or not it was built.
  # When it is absent every call answers `{:error, :unavailable}` and
  # `backend: :nif` falls through to the native implementation.

  describe "when the NIF is unavailable" do
    @describetag :nif_optional

    test "available?/0 answers without raising" do
      assert is_boolean(Nif.available?())
    end

    test "split/3 answers with a tagged tuple rather than raising" do
      result = Nif.split("hello", :word)
      assert match?({:ok, _}, result) or result == {:error, :unavailable}
    end

    test "an unknown break type is an error, not a crash" do
      assert {:error, :unavailable} = Nif.split("hello", :nonsense)
    end

    test "a non-binary argument is an error, not a crash" do
      assert {:error, :unavailable} = Nif.split(:not_a_string, :word)
    end
  end

  describe "backend: :nif is always safe" do
    test "falls back to the native implementation when unavailable" do
      assert Unicode.String.split("Hello there", break: :word, trim: true) ==
               ["Hello", "there"]

      # Whether or not the NIF is present, a sensible answer comes back.
      segments = Unicode.String.split("Hello there", break: :word, backend: :nif, trim: true)
      assert "Hello" in segments
      assert "there" in segments
    end

    test "an unrecognised backend falls back rather than failing" do
      assert Unicode.String.split("Hello", break: :word, backend: :nonsense) == ["Hello"]
    end
  end

  describe "when the NIF is available" do
    test "agrees with the native implementation on plain ASCII words" do
      if Nif.available?() do
        text = "The quick brown fox jumps over the lazy dog."
        {:ok, from_nif} = Nif.split(text, :word, "en")
        assert Enum.join(from_nif) == text
        assert "quick" in from_nif
      end
    end

    test "round-trips every break type" do
      if Nif.available?() do
        text = "One two. Three four."

        for break <- [:grapheme, :word, :line, :sentence] do
          {:ok, segments} = Nif.split(text, break, "en")
          assert Enum.join(segments) == text, "#{break} did not round-trip"
        end
      end
    end

    test "break_type/1 maps every break name to an ICU iterator type" do
      types = Enum.map([:grapheme, :word, :line, :sentence], &Nif.break_type/1)

      assert Enum.all?(types, &is_integer/1)
      assert Enum.uniq(types) == types
    end

    test "the benchmark helpers prepare an iterator and run it" do
      if Nif.available?() do
        # These exist so the benchmark can time ICU without the per-call NIF
        # marshalling. `benchmark_run/2` returns the boundary count.
        {:ok, prepared} = Nif.benchmark_prepare("hello world", Nif.break_type(:word), "en")
        assert Nif.benchmark_run(prepared, 3) > 0
      end
    end
  end
end
