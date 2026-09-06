/*
 * Optional ICU4C break-iterator backend for unicode_string.
 *
 * This is the whole segmentation operation as a consumer would use it: a UTF-8
 * binary goes in, a list of UTF-8 binaries comes out. Everything the boundary
 * between the BEAM and ICU costs — the UTF-8 to UTF-16 conversion, iterator
 * construction, and building the result terms — is inside the call and is
 * therefore paid for on every use. That is deliberate; see
 * benchee/nif_compare.exs, which measures this against the native Elixir
 * implementation and against ICU with those costs excluded.
 */
#include <string.h>
#include <stdlib.h>
#include <erl_nif.h>
#include <unicode/ubrk.h>
#include <unicode/ustring.h>
#include <unicode/utypes.h>

static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_error;
static ErlNifResourceType *PREPARED_RES;

/*
 * Holds text already converted to UTF-16 together with a live iterator, so a
 * benchmark can time ICU's segmentation without the conversion, the iterator
 * construction or the term building. Only benchmark_prepare/3 and
 * benchmark_run/2 use it; ordinary segmentation goes through split/3.
 */
typedef struct {
    UChar *text;
    int32_t length;
    UBreakIterator *iterator;
} prepared_t;

static void prepared_dtor(ErlNifEnv *env, void *obj) {
    prepared_t *prepared = (prepared_t *)obj;
    if (prepared->iterator) ubrk_close(prepared->iterator);
    if (prepared->text) free(prepared->text);
}

static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM info) {
    atom_ok = enif_make_atom(env, "ok");
    atom_error = enif_make_atom(env, "error");

    PREPARED_RES = enif_open_resource_type(env, NULL, "unicode_string_prepared",
                                           prepared_dtor, ERL_NIF_RT_CREATE, NULL);
    return PREPARED_RES == NULL ? 1 : 0;
}

static ERL_NIF_TERM error_tuple(ErlNifEnv *env, const char *reason) {
    return enif_make_tuple2(env, atom_error, enif_make_atom(env, reason));
}

/*
 * split(Text :: binary, Type :: 0..3, Locale :: binary) ->
 *     {ok, [binary]} | {error, atom}
 *
 * Type follows UBreakIteratorType: 0 character, 1 word, 2 line, 3 sentence.
 */
static ERL_NIF_TERM split(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary text_bin, locale_bin;
    int type;
    char locale[64];
    UErrorCode status = U_ZERO_ERROR;

    if (!enif_inspect_binary(env, argv[0], &text_bin)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &type)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &locale_bin)) return enif_make_badarg(env);
    if (type < 0 || type > 3) return enif_make_badarg(env);

    size_t locale_length =
        locale_bin.size < sizeof(locale) - 1 ? locale_bin.size : sizeof(locale) - 1;
    memcpy(locale, locale_bin.data, locale_length);
    locale[locale_length] = '\0';

    if (text_bin.size == 0) {
        return enif_make_tuple2(env, atom_ok, enif_make_list(env, 0));
    }

    /* UTF-16 needs at most as many units as the UTF-8 input has bytes. */
    int32_t capacity = (int32_t)text_bin.size + 1;
    UChar *utf16 = (UChar *)malloc((size_t)capacity * sizeof(UChar));
    if (!utf16) return error_tuple(env, "out_of_memory");

    int32_t utf16_length = 0;
    u_strFromUTF8(utf16, capacity, &utf16_length, (const char *)text_bin.data,
                  (int32_t)text_bin.size, &status);
    if (U_FAILURE(status)) {
        free(utf16);
        return error_tuple(env, "invalid_utf8");
    }

    UBreakIterator *iterator =
        ubrk_open((UBreakIteratorType)type, locale, utf16, utf16_length, &status);
    if (U_FAILURE(status)) {
        free(utf16);
        return error_tuple(env, "break_iterator");
    }

    /* Collect boundaries first so the result list can be built back to front. */
    int32_t *boundaries = (int32_t *)malloc((size_t)(utf16_length + 2) * sizeof(int32_t));
    if (!boundaries) {
        ubrk_close(iterator);
        free(utf16);
        return error_tuple(env, "out_of_memory");
    }

    int32_t count = 0;
    int32_t position = ubrk_first(iterator);
    boundaries[count++] = position;
    while ((position = ubrk_next(iterator)) != UBRK_DONE) {
        boundaries[count++] = position;
    }

    ERL_NIF_TERM list = enif_make_list(env, 0);
    int failed = 0;

    for (int32_t i = count - 1; i > 0; i--) {
        int32_t from = boundaries[i - 1];
        int32_t to = boundaries[i];
        int32_t needed = 0;
        UErrorCode segment_status = U_ZERO_ERROR;

        u_strToUTF8(NULL, 0, &needed, utf16 + from, to - from, &segment_status);
        if (segment_status != U_BUFFER_OVERFLOW_ERROR && U_FAILURE(segment_status)) {
            failed = 1;
            break;
        }

        ERL_NIF_TERM segment;
        unsigned char *buffer = enif_make_new_binary(env, (size_t)needed, &segment);
        segment_status = U_ZERO_ERROR;
        u_strToUTF8((char *)buffer, needed, &needed, utf16 + from, to - from, &segment_status);
        if (U_FAILURE(segment_status)) {
            failed = 1;
            break;
        }

        list = enif_make_list_cell(env, segment, list);
    }

    free(boundaries);
    ubrk_close(iterator);
    free(utf16);

    if (failed) return error_tuple(env, "utf8_conversion");
    return enif_make_tuple2(env, atom_ok, list);
}

/*
 * benchmark_prepare(Text, Type, Locale) -> {ok, Prepared} | {error, atom}
 *
 * Converts and builds the iterator once, outside any timed region.
 */
static ERL_NIF_TERM benchmark_prepare(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary text_bin, locale_bin;
    int type;
    char locale[64];
    UErrorCode status = U_ZERO_ERROR;

    if (!enif_inspect_binary(env, argv[0], &text_bin)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &type)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &locale_bin)) return enif_make_badarg(env);
    if (type < 0 || type > 3) return enif_make_badarg(env);

    size_t locale_length =
        locale_bin.size < sizeof(locale) - 1 ? locale_bin.size : sizeof(locale) - 1;
    memcpy(locale, locale_bin.data, locale_length);
    locale[locale_length] = '\0';

    int32_t capacity = (int32_t)text_bin.size + 1;
    UChar *utf16 = (UChar *)malloc((size_t)capacity * sizeof(UChar));
    if (!utf16) return error_tuple(env, "out_of_memory");

    int32_t utf16_length = 0;
    u_strFromUTF8(utf16, capacity, &utf16_length, (const char *)text_bin.data,
                  (int32_t)text_bin.size, &status);
    if (U_FAILURE(status)) {
        free(utf16);
        return error_tuple(env, "invalid_utf8");
    }

    UBreakIterator *iterator =
        ubrk_open((UBreakIteratorType)type, locale, utf16, utf16_length, &status);
    if (U_FAILURE(status)) {
        free(utf16);
        return error_tuple(env, "break_iterator");
    }

    prepared_t *prepared = enif_alloc_resource(PREPARED_RES, sizeof(prepared_t));
    prepared->text = utf16;
    prepared->length = utf16_length;
    prepared->iterator = iterator;

    ERL_NIF_TERM term = enif_make_resource(env, prepared);
    enif_release_resource(prepared);
    return enif_make_tuple2(env, atom_ok, term);
}

/*
 * benchmark_run(Prepared, Iterations) -> integer
 *
 * Runs `Iterations` complete segmentation passes inside C, converting each
 * segment back to UTF-8 so the work matches what split/3 does, minus the term
 * building. ubrk_setText resets ICU's boundary cache each pass; without it a
 * break type with few boundaries replays the first pass instead of segmenting.
 */
static ERL_NIF_TERM benchmark_run(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    prepared_t *prepared;
    int iterations;
    long total = 0;

    if (!enif_get_resource(env, argv[0], PREPARED_RES, (void **)&prepared)) {
        return enif_make_badarg(env);
    }
    if (!enif_get_int(env, argv[1], &iterations)) return enif_make_badarg(env);

    int32_t capacity = prepared->length * 4 + 1;
    char *scratch = (char *)malloc((size_t)capacity);
    if (!scratch) return error_tuple(env, "out_of_memory");

    for (int i = 0; i < iterations; i++) {
        UErrorCode reset = U_ZERO_ERROR;
        ubrk_setText(prepared->iterator, prepared->text, prepared->length, &reset);

        int32_t from = ubrk_first(prepared->iterator);
        int32_t to;
        while ((to = ubrk_next(prepared->iterator)) != UBRK_DONE) {
            UErrorCode status = U_ZERO_ERROR;
            int32_t written = 0;
            u_strToUTF8(scratch, capacity, &written, prepared->text + from, to - from, &status);
            total += written;
            from = to;
        }
    }

    free(scratch);
    return enif_make_long(env, total);
}

static ERL_NIF_TERM available(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    return enif_make_atom(env, "true");
}

static ErlNifFunc funcs[] = {
    {"do_split", 3, split, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"benchmark_prepare", 3, benchmark_prepare, 0},
    {"benchmark_run", 2, benchmark_run, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"nif_available?", 0, available, 0}
};

ERL_NIF_INIT(Elixir.Unicode.String.Nif, funcs, load, NULL, NULL, NULL)
