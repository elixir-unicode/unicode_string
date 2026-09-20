defmodule Unicode.String.Nif do
  @moduledoc """
  Optional ICU4C backend for segmentation.

  ICU's break iterator is one to two orders of magnitude faster than the native
  Elixir implementation on rule-driven segmentation. This module makes it
  available for workloads where that matters, without making ICU a requirement
  for everyone else.

  ### Enabling

  The NIF is opt-in and needs:

  1. ICU system libraries. On macOS `brew install icu4c`, on Debian or Ubuntu
     `apt install libicu-dev`.

  2. The `:elixir_make` dependency, which is optional and not fetched by default.

  3. The build enabled by either:
     * the environment variable `UNICODE_STRING_NIF=true mix compile`, or
     * `config :unicode_string, :nif, true` in `config.exs`.

  The config key must be in `config.exs` rather than `runtime.exs`, because it
  is read at compile time to decide whether to add the `:elixir_make` compiler.

  ### Using it

  Pass `backend: :nif` to `Unicode.String.split/2`. When the NIF is unavailable
  the native implementation is used instead, so the option is always safe:

      Unicode.String.split("Hello there", break: :word, backend: :nif)

  `available?/0` reports whether the shared library loaded.

  ### Differences from the native implementation

  The two are not always identical. ICU applies its own locale tailorings, most
  visibly the CJK `loose`/`normal`/`strict` line break modes that the native
  implementation does not have, and it uses its own dictionaries for Chinese,
  Japanese, Thai, Lao, Khmer and Burmese rather than the ones this library
  downloads. Where the two disagree, the Conformance guide describes why.

  """

  @on_load :init

  @break_types %{grapheme: 0, word: 1, line: 2, sentence: 3}
  @break_names Map.keys(@break_types)

  @doc false
  def init do
    path =
      :unicode_string
      |> Application.app_dir("priv/unicode_string_nif")
      |> String.to_charlist()

    # A missing or unbuildable NIF is the normal case, not an error: the module
    # still loads and `available?/0` answers false.
    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  @doc """
  Returns whether the ICU backend is available.

  ### Returns

  * `true` if the NIF shared library loaded.

  * `false` if it was not built, or if the ICU libraries are missing.

  ### Examples

      iex> is_boolean(Unicode.String.Nif.available?())
      true

  """
  @spec available?() :: boolean()
  def available? do
    # Replaced by the NIF. The stub raises rather than returning `false` so the
    # compiler cannot infer a constant result and prune the loaded branch at
    # every call site.
    nif_available?()
  rescue
    ErlangError -> false
  end

  @doc false
  def nif_available?, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Splits `string` using the ICU break iterator.

  ### Arguments

  * `string` is any `t:String.t/0`.

  * `break` is one of `:grapheme`, `:word`, `:line` or `:sentence`.

  * `locale` is an ICU locale identifier such as `"en"` or `"ja"`. The default
    is `"root"`.

  ### Returns

  * `{:ok, segments}` where `segments` is a list of `t:String.t/0`, or

  * `{:error, reason}`, including `{:error, :unavailable}` when the NIF was not
    built.

  ### Examples

      iex> case Unicode.String.Nif.split("Hello there", :word) do
      ...>   {:ok, segments} -> Enum.member?(segments, "Hello")
      ...>   {:error, :unavailable} -> true
      ...> end
      true

  """
  @spec split(String.t(), atom(), String.t()) ::
          {:ok, [String.t()]} | {:error, atom()}
  def split(string, break, locale \\ "root")

  def split(string, break, locale)
      when is_binary(string) and break in @break_names and is_binary(locale) do
    do_split(string, Map.fetch!(@break_types, break), locale)
  rescue
    ErlangError -> {:error, :unavailable}
  end

  def split(_string, _break, _locale), do: {:error, :unavailable}

  @doc false
  def do_split(_string, _type, _locale), do: :erlang.nif_error(:nif_not_loaded)

  # Benchmark support. `benchmark_prepare/3` converts the text to UTF-16 and
  # builds an iterator once; `benchmark_run/2` then performs whole segmentation
  # passes inside C. Together they measure ICU's segmentation with the cost of
  # the BEAM boundary excluded, which is what `benchee/nif_compare.exs` needs in
  # order to show how much of ICU's advantage that boundary consumes. They are
  # not part of the public interface and are useless for actually segmenting
  # anything, since they return a byte count rather than the segments.

  @doc false
  def benchmark_prepare(_string, _type, _locale), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def benchmark_run(_prepared, _iterations), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def break_type(break) when break in @break_names, do: Map.fetch!(@break_types, break)
end
