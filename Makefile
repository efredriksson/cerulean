include $(wildcard .env)

SRCS := $(shell find src/formatter -type f -name "*.tl")
SRCS_LINT := $(patsubst src/%, ./src/%, $(SRCS))

FORMATTER := tl run src/formatter/init.tl --

lint:
	tl check ${SRCS_LINT}
	${FORMATTER} --check src/formatter

format:
	${FORMATTER} src/formatter

test: lint
	busted spec/

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
