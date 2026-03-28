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
