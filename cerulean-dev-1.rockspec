rockspec_format = "3.0"
package = "cerulean"
version = "dev-1"

source = {
   url = "git+https://github.com/efredriksson/cerulean",
   branch = "main",
}

description = {
   summary = "A formatter for the Teal programming language",
   detailed = [[
      Cerulean formats Teal source files with configurable indentation,
      line width, and require-statement sorting. It can be run as a CLI
      tool or integrated into editor workflows.
   ]],
   homepage = "https://github.com/efredriksson/cerulean",
   license = "MIT",
}

dependencies = {
   "lua >= 5.1",
   "luafilesystem",
   "tl",
}

build = {
   type = "command",
   build_command = "make compile",
   install_command = "make install LUADIR=$(LUADIR) BINDIR=$(BINDIR)",
}
