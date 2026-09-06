/*
 * A minimal ICU break-iterator NIF, used only by benchee/icu_compare.exs.
 *
 * The point of the split between prepare/3 and run/2 is measurement fairness:
 * UTF-8 to UTF-16 conversion and iterator construction happen once, in
 * prepare/3, and are never timed. run/2 then performs `iterations` complete
 * break-iteration passes inside C, so the single NIF boundary crossing is
 * amortised across all of them and effectively drops out of the result.
 */
#include <string.h>
#include <stdlib.h>
#include <erl_nif.h>
#include <unicode/ubrk.h>
#include <unicode/ustring.h>
#include <unicode/utypes.h>

static ErlNifResourceType *ICU_RES;

typedef struct {
    UChar *text;
    int32_t len;
    UBreakIterator *bi;
} icu_res_t;

static void icu_res_dtor(ErlNifEnv *env, void *obj) {
    icu_res_t *r = (icu_res_t *)obj;
    if (r->bi) ubrk_close(r->bi);
    if (r->text) free(r->text);
}

static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM info) {
    ICU_RES = enif_open_resource_type(env, NULL, "icu_res", icu_res_dtor,
                                      ERL_NIF_RT_CREATE, NULL);
    return ICU_RES == NULL ? 1 : 0;
}

static ERL_NIF_TERM prepare(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary text_bin, loc_bin;
    int type;
    char locale[64];
    UErrorCode status = U_ZERO_ERROR;

    if (!enif_inspect_binary(env, argv[0], &text_bin)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &type)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &loc_bin)) return enif_make_badarg(env);

    size_t ll = loc_bin.size < sizeof(locale) - 1 ? loc_bin.size : sizeof(locale) - 1;
    memcpy(locale, loc_bin.data, ll);
    locale[ll] = '\0';

    int32_t cap = (int32_t)text_bin.size + 1;
    UChar *u = (UChar *)malloc((size_t)cap * sizeof(UChar));
    int32_t ulen = 0;
    u_strFromUTF8(u, cap, &ulen, (const char *)text_bin.data,
                  (int32_t)text_bin.size, &status);
    if (U_FAILURE(status)) {
        free(u);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                                enif_make_atom(env, "utf8_conversion"));
    }

    UBreakIterator *bi = ubrk_open((UBreakIteratorType)type, locale, u, ulen, &status);
    if (U_FAILURE(status)) {
        free(u);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                                enif_make_atom(env, "ubrk_open"));
    }

    icu_res_t *r = enif_alloc_resource(ICU_RES, sizeof(icu_res_t));
    r->text = u;
    r->len = ulen;
    r->bi = bi;
    ERL_NIF_TERM term = enif_make_resource(env, r);
    enif_release_resource(r);
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), term);
}

static ERL_NIF_TERM run(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    icu_res_t *r;
    int iterations;
    long count = 0;

    if (!enif_get_resource(env, argv[0], ICU_RES, (void **)&r)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &iterations)) return enif_make_badarg(env);

    for (int i = 0; i < iterations; i++) {
        int32_t p = ubrk_first(r->bi);
        while ((p = ubrk_next(r->bi)) != UBRK_DONE) count++;
    }
    return enif_make_long(env, count);
}

/*
 * As run/2, but also converts each segment back to UTF-8 into a scratch
 * buffer. `Unicode.String.split/2` materialises its segments, so comparing it
 * against boundary iteration alone would flatter ICU; this gives a second
 * ICU figure that pays for segment extraction too. The native side still
 * additionally allocates Erlang binaries, which C never does - see the notes
 * in benchee/icu_compare.exs.
 */
static ERL_NIF_TERM run_extract(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    icu_res_t *r;
    int iterations;
    long count = 0;

    if (!enif_get_resource(env, argv[0], ICU_RES, (void **)&r)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &iterations)) return enif_make_badarg(env);

    int32_t cap = r->len * 4 + 1;
    char *scratch = (char *)malloc((size_t)cap);
    if (!scratch) return enif_make_badarg(env);

    for (int i = 0; i < iterations; i++) {
        int32_t prev = ubrk_first(r->bi);
        int32_t p;
        while ((p = ubrk_next(r->bi)) != UBRK_DONE) {
            UErrorCode status = U_ZERO_ERROR;
            int32_t out = 0;
            u_strToUTF8(scratch, cap, &out, r->text + prev, p - prev, &status);
            count += out;
            prev = p;
        }
    }
    free(scratch);
    return enif_make_long(env, count);
}

static ErlNifFunc funcs[] = {
    {"prepare", 3, prepare, 0},
    {"run", 2, run, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"run_extract", 2, run_extract, ERL_NIF_DIRTY_JOB_CPU_BOUND}
};

ERL_NIF_INIT(Elixir.IcuBreak, funcs, load, NULL, NULL, NULL)
