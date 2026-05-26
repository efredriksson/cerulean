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
	install -m 755 bin/ceru $(BINDIR)/ceru

rock:
	luarocks make cerulean-dev-1.rockspec

rock-artifacts:
	@test -n "$(VERSION)" || (echo "Usage: make rock-artifacts VERSION=x.y.z" && exit 1)
	sed -i 's/local version = "dev"/local version = "$(VERSION)"/' src/cerulean/cli.tl
	$(MAKE) compile
	sed 's/version = "dev-1"/version = "$(VERSION)-1"/; s|url = "git+https://github.com/efredriksson/cerulean"|url = "https://github.com/efredriksson/cerulean/releases/download/v$(VERSION)/cerulean-$(VERSION).tar.gz"|; s/branch = "main"/md5 = "__HASH__"/' \
		cerulean-dev-1.rockspec > cerulean-$(VERSION)-1.rockspec
	tar czf cerulean-$(VERSION).tar.gz \
		--transform 's|^|cerulean-$(VERSION)/|' \
		bin/ dist/ LICENSE LICENSES/ README.MD
	sed -i "s/__HASH__/$$(md5sum cerulean-$(VERSION).tar.gz | cut -d' ' -f1)/" cerulean-$(VERSION)-1.rockspec

release-upload:
	@test -n "$(VERSION)" || (echo "Usage: make release-upload VERSION=x.y.z" && exit 1)
	luarocks upload cerulean-$(VERSION)-1.rockspec --api-key=$(LUAROCKS_API_KEY)

.PHONY: fuzz fuzz-corpus fuzz-deep
fuzz:
	tl run fuzz/fuzz.tl -- $(ARGS)

fuzz-corpus:
	tl run fuzz/fuzz.tl -- --seed-corpus src/cerulean,spec/cerulean/fixtures --count 5000 --mutations-per-file 1 $(ARGS)

fuzz-deep:
	tl run fuzz/fuzz.tl -- --depth 40 --trivia-rate 0.4 --count 5000 $(ARGS)
