# cerulean

An opinionated code formatter for the [Teal](https://teal-language.org/) programming language.

## Installation

```sh
luarocks install cerulean
```

This installs the `cerulean` binary and the `cerulean.*` Lua modules.

**Dependencies:** Lua 5.1+, [luafilesystem](https://lunarmodules.github.io/luafilesystem/), [tl](https://luarocks.org/modules/hisham/tl)

## Usage

Format files in place:

```sh
ceru src/
ceru src/myfile.tl
```

Check whether files would format:

```sh
ceru --check src/
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--check` | off | Report files that would be reformatted; exit 1 if any |
| `--indent <n>` | `4` | Indentation width in spaces |
| `--line-length <n>` | `88` | Target line length |
| `--no-sort-requires` | — | Disable sorting of `require` statements |

### Configuration via tlconfig.lua

Options can be set project-wide in `tlconfig.lua` under a `cerulean` key. CLI flags override config file values.

```lua
return {
   cerulean = {
      indent_width = 2,
      max_line_width = 100,
      sort_requires = false,
   },
}
```

### fmt: off / fmt: on

Wrap regions you want left untouched in formatter directives:

```teal
-- fmt: off
local hand_formatted = {1,    2,   3,
                        100,  200, 300}
-- fmt: on
```

## Development

Dependencies: [Lua](https://www.lua.org/), [LuaRocks](https://luarocks.org/), [Make](https://www.gnu.org/software/make/), [tl](https://teal-language.org/), [busted](https://lunarmodules.github.io/busted/), [luafilesystem](https://lunarmodules.github.io/luafilesystem/).

```sh
sudo apt install luarocks make
sudo luarocks install tl
sudo luarocks install busted
sudo luarocks install luafilesystem
```

| Command | Description |
|---------|-------------|
| `make lint` | Type-check and run formatter in `--check` mode |
| `make format` | Format the formatter's own source |
| `make test` | Run lint + test suite |
| `make compile` | Compile Teal sources to `dist/cerulean/` |
| `make rock` | Install locally via LuaRocks |
