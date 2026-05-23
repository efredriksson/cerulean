# Claude Code conventions for this repository

See [ARCHITECTURE.md](src/cerulean/ARCHITECTURE.md) for a full overview of the codebase.

## Skills

Invoke these skills at the start of relevant work in this repo:

- `/teal` — when reading or editing `.tl` files
- `/busted` — when writing or running tests
- `/code-design` — when designing or refactoring code structure
- `/comment-code` — when writing code comments

If a skill is not available, proceed and report it to the user at the end of the task.

## Workflow

After making changes, run `busted spec/` to verify logic of the code is correct, then `make lint` to ensure the code conforms and that the formatter formatting itself looks reasonable. Running `make format` will format the code which might be neccessary for new code or when new formatting features/updates are added.

To run the formatter on a file: `tl run src/cerulean/init.tl -- <file>`. For scripted investigations, write a `.tl` script and run it with `tl run` — always prefer Teal scripts over shell scripts or Lua scripts.

**Fuzz bugs.** `make fuzz` generates `fuzz/corpus/` and writes failures to `fuzz/regressions_spec.lua`. When the user reports fuzz failures, read `fuzz/regressions_spec.lua` directly — do not re-run discovery. To see test failures and their diffs, run `busted fuzz/regressions_spec.lua -o gtest`, the output have before/after for all failures. Do not write scripts to reproduce fuzz failures; `helpers.check()` already handles idempotency. Fix workflow: write a focused test in `spec/` → fix → `busted spec/` + `busted fuzz/regressions_spec.lua`. Corpus files are untracked.

**Spec helpers.** `helpers.check(src)` — assert unchanged. `helpers.format(input, expected)` — assert formats as expected. `helpers.parse_error(src)` — assert parser error for input.

**Debug logging in tests.** Set `CERULEAN_TEST_LOG_LEVEL=debug` (or `info`) before `busted …` to surface `[fmt:debug]` lines. Use with `busted --filter="<pattern>"` to keep output small.
