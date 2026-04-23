include $(wildcard .env)

SRCS := $(shell find src/cerulean -type f -name "*.tl")
SRCS_LINT := $(patsubst src/%, ./src/%, $(SRCS))
TL_SOURCES := $(filter-out %.d.tl, $(SRCS))
TL_COMPILED := $(patsubst src/cerulean/%.tl, dist/cerulean/%.lua, $(TL_SOURCES))

LUADIR ?= /usr/local/share/lua/5.4
BINDIR ?= /usr/local/bin

FORMATTER := tl run src/cerulean/init.tl --

lint:
	tl check ${SRCS_LINT}
	${FORMATTER} --check src/cerulean

format:
	${FORMATTER} src/cerulean

test: lint
	busted spec/

dist/cerulean/%.lua: src/cerulean/%.tl | dist/cerulean
	tl gen $< -o $@

dist/cerulean:
	mkdir -p $@

compile: $(TL_COMPILED)

install: compile
	install -d $(LUADIR)/cerulean
	cp dist/cerulean/*.lua $(LUADIR)/cerulean/
	install -d $(BINDIR)
	install -m 755 bin/cerulean $(BINDIR)/cerulean

rock:
	luarocks make cerulean-dev-1.rockspec

.PHONY: fuzz
fuzz:
	@test -d .venv || (echo "ERROR: .venv not found. Run: python3 -m venv .venv && .venv/bin/pip install grammarinator" && exit 1)
	mkdir -p fuzz/gen fuzz/corpus
	.venv/bin/grammarinator-process fuzz/Teal.g4 -o fuzz/gen/ --no-actions
	.venv/bin/grammarinator-generate TealGenerator.TealGenerator \
		-r chunk -d 20 \
		-o fuzz/corpus/test_%d.tl -n 1000 \
		--sys-path fuzz/gen/ \
		-s grammarinator.runtime.serializer.simple_space_serializer
	LUA_PATH="./src/?.lua;;" lua fuzz/fuzz.lua fuzz/corpus/*.tl
