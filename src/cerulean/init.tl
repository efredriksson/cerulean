-- CLI entry point. Reads files, calls rewriter.rewrite, writes output (or checks in --check mode).
-- Run with: tl run src/cerulean/init.tl -- [--check] [--no-sort-requires] [--log-level <level>] [--indent <n>] [--line-length <n>] [file|dir...]
local cli = require("cerulean.cli")

local code = cli.run(
    arg,
    cli.new_printer(
        function(msg: string) io.stdout:write(msg .. "\n") end,
        function(msg: string) io.stderr:write(msg .. "\n") end
    )
)
os.exit(code)
