include $(wildcard .env)

SRCS := $(shell find src -type f -name "*.tl")
SRCS_LINT := $(patsubst src/%, ./src/%, $(SRCS))
TRANSPILED := $(patsubst src/%.tl, dist/%.lua, $(SRCS))
ASSETS := $(shell find assets -type f)
DIST_ASSETS := $(patsubst %, dist/%, $(ASSETS))
LUTRO_DIST_DIR ?= $(CURDIR)
LUTRO_DIST_NAME ?= explodelon.lutro
LUTRO_DIST_PATH ?= ${LUTRO_DIST_DIR}/${LUTRO_DIST_NAME}

dist/%.lua : src/%.tl | dist
	@mkdir -p $(@D) && tl gen $< -o $@

dist/assets/%: assets/% | dist
	@mkdir -p $(@D) && cp $< $@

dist:
	mkdir -p $@

clean:
	rm -rf ./dist || true

${LUTRO_DIST_PATH}: $(TRANSPILED) $(DIST_ASSETS)
	cd dist && zip -r $@ .

package: ${LUTRO_DIST_PATH}

FORMATTER := tl run src/formatter/init.tl --

lint:
	tl check ${SRCS_LINT}
	${FORMATTER} --check ${SRCS_LINT}

format:
	${FORMATTER} ${SRCS_LINT}

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
	lua fuzz/fuzz.lua fuzz/corpus/*.tl
