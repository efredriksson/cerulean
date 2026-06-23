-- CLI entry point. Reads files, calls rewriter.rewrite, writes output (or checks in --check mode).
-- Run with: tl run src/cerulean/init.tl -- [--check] [--no-sort-requires] [--log-level <level>] [--indent <n>] [--line-length <n>] [file|dir...]
local cli = require("cerulean.cli")

local code = cli.run(
    arg,
    cli.Stdio.new(
        function(text: string) io.stdout:write(text) end,
        function(text: string) io.stderr:write(text) end,
        function(): string return io.stdin:read("*a") end
    )
)
os.exit(code)
