#!/usr/bin/env bash
# Builds the ICU break-iterator NIF used by benchee/icu_compare.exs.
#
# This is a benchmark-only artefact: it is not part of the library build and
# nothing in lib/ or test/ depends on it.
set -euo pipefail

ICU_PREFIX="${ICU_PREFIX:-$(brew --prefix icu4c@78 2>/dev/null || brew --prefix icu4c)}"
ERTS_INCLUDE="${ERTS_INCLUDE:-$(erl -noshell -eval \
  'io:format("~ts/erts-~ts/include", [code:root_dir(), erlang:system_info(version)]), halt().')}"

# Erlang installs erl_nif.h under usr/include as well; prefer whichever exists.
if [ ! -f "$ERTS_INCLUDE/erl_nif.h" ]; then
  ERTS_INCLUDE="$(erl -noshell -eval 'io:format("~ts/usr/include", [code:root_dir()]), halt().')"
fi

echo "ICU:  $ICU_PREFIX"
echo "ERTS: $ERTS_INCLUDE"

cc -O2 -fPIC -shared -undefined dynamic_lookup \
  -I"$ERTS_INCLUDE" \
  -I"$ICU_PREFIX/include" \
  -L"$ICU_PREFIX/lib" \
  -licuuc -licui18n -licudata \
  -Wl,-rpath,"$ICU_PREFIX/lib" \
  -o "$(dirname "$0")/icu_break.so" \
  "$(dirname "$0")/icu_break.c"

echo "built: $(dirname "$0")/icu_break.so"
