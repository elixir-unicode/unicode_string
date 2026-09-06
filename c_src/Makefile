# Builds the optional ICU4C break-iterator NIF.
#
# The NIF is opt-in: `mix.exs` only adds the :elixir_make compiler when
# UNICODE_STRING_NIF=true is set or `config :unicode_string, :nif, true` is in
# config.exs, so this Makefile is not run in a default build.

ERL ?= erl
PRIVDIR = ./priv

NIF_DIR = c_src
NIF_ENV = c_src/env.mk

NIF_SOURCES = $(NIF_DIR)/unicode_string_nif.c
NIF_OBJS = $(NIF_DIR)/unicode_string_nif.o
NIF_SO = $(PRIVDIR)/unicode_string_nif.so

UNAME_SYS := $(shell uname -s)
UNAME_ARCH := $(shell uname -m)

ifeq ($(UNAME_SYS), Darwin)
	CC ?= cc
	CFLAGS ?= -O3 -std=c11 -Wall
	LDFLAGS = -flat_namespace -undefined dynamic_lookup
else ifeq ($(UNAME_SYS), FreeBSD)
	CC ?= cc
	CFLAGS ?= -O3 -std=c11 -finline-functions -Wall
else
	CC ?= gcc
	CFLAGS ?= -O3 -std=c11 -finline-functions -Wall
endif

CFLAGS += -fPIC -I$(ERTS_INCLUDE_DIR)
LDFLAGS += -shared

# ICU detection. Homebrew keeps icu4c keg-only, so pkg-config needs pointing at
# it; the versioned icu4c@NN formulae are checked as well as the unversioned one.
ifeq ($(UNAME_SYS), Darwin)
  ICU_PREFIX := $(shell for d in /usr/local/opt/icu4c /opt/homebrew/opt/icu4c \
                                 /usr/local/opt/icu4c@78 /opt/homebrew/opt/icu4c@78 \
                                 /usr/local/opt/icu4c@77 /opt/homebrew/opt/icu4c@77; do \
                          [ -d "$$d/lib/pkgconfig" ] && echo "$$d" && break; \
                        done)
  ifneq ($(ICU_PREFIX),)
    export PKG_CONFIG_PATH := $(ICU_PREFIX)/lib/pkgconfig:$(PKG_CONFIG_PATH)
  endif
endif

ICU_CFLAGS = $(shell pkg-config --cflags icu-uc 2>/dev/null)
ICU_LIBS = $(shell pkg-config --libs icu-uc 2>/dev/null)

ifeq ($(ICU_LIBS),)
  ifneq ($(ICU_PREFIX),)
    ICU_CFLAGS = -I$(ICU_PREFIX)/include
    ICU_LIBS = -L$(ICU_PREFIX)/lib -licuuc -licudata
  endif
endif

ifeq ($(ICU_LIBS),)
  $(error ICU libraries not found. On macOS: brew install icu4c. On Debian/Ubuntu: apt install libicu-dev)
endif

# Record the ICU library path so the loader finds it without DYLD/LD_LIBRARY_PATH.
ifneq ($(ICU_PREFIX),)
  ICU_LIBS += -Wl,-rpath,$(ICU_PREFIX)/lib
endif

all: $(NIF_ENV) $(NIF_SO)

clean:
	@rm -rf $(NIF_SO) $(NIF_OBJS)

distclean: clean
	@rm -rf $(NIF_ENV)

$(NIF_SO): $(NIF_OBJS)
	@mkdir -p $(PRIVDIR)
	$(CC) $(NIF_OBJS) $(LDFLAGS) $(ICU_LIBS) -o $(NIF_SO)

%.o: %.c
	$(CC) -c $(CFLAGS) $(ICU_CFLAGS) $< -o $@

$(NIF_ENV):
	@$(ERL) -eval "file:write_file(\"$(NIF_ENV)\", \
		io_lib:format(\"ERTS_INCLUDE_DIR ?= ~s/erts-~s/include~n\", \
		[code:root_dir(), erlang:system_info(version)])), \
		halt()."

-include $(NIF_ENV)
