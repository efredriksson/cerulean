# cerulean

An opinionated code formatter for the [Teal](https://teal-language.org/) programming language.

Full documentation at **[efredriksson.github.io/cerulean](https://efredriksson.github.io/cerulean)**.

## Installation

```sh
luarocks install cerulean
```

**Dependencies:** Lua 5.1+, [luafilesystem](https://lunarmodules.github.io/luafilesystem/), [tl](https://luarocks.org/modules/hisham/tl)

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

### Docs

Install mdBook (v0.5.2):

```sh
curl -sSL https://github.com/rust-lang/mdBook/releases/download/v0.5.2/mdbook-v0.5.2-x86_64-unknown-linux-gnu.tar.gz | tar -xz
sudo mv mdbook /usr/local/bin/
```

Then:

```sh
mdbook serve docs/
```

Builds and serves the docs at `http://localhost:3000` with live reload.
