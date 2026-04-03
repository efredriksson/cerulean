-- CLI entry point. Reads files, calls rewriter.rewrite, writes output (or checks in --check mode).
-- Run with: tl run src/formatter/init.tl -- [--check] [--log-level <level>] <file...>
local fmt_logger = require("formatter.fmt_logger")
local rewriter = require("formatter.rewriter")

local record Args
    check_only: boolean
    log_level: string
    files: {string}
end

function Args.new(check_only: boolean, log_level: string, files: {string}): Args
    local self: Args = setmetatable({}, { __index = Args })
    self.check_only = check_only
    self.log_level = log_level
    self.files = files
    return self
end

local function read_file(path: string): string, string
    local file, open_err = io.open(path, "r")
    if not file then
        return nil, open_err
    end
    local content = file:read("*a")
    file:close()
    return content, nil
end

local function write_file(path: string, content: string): string
    local file, open_err = io.open(path, "w")
    if not file then
        return open_err
    end
    file:write(content)
    file:close()
    return nil
end

local function write_error(msg: string, ...: string)
    io.stderr:write(string.format(msg .. "\n", ...))
end

local function write_ok(msg: string, ...: string)
    io.stdout:write(string.format(msg .. "\n", ...))
end

local function parse_args(script_args: {string}): Args
    local check_only = false
    local log_level = "nothing"
    local files: {string} = {}

    local i = 1
    while i <= #script_args do
        local value = script_args[i]
        if value == "--check" then
            check_only = true
        elseif value == "--log-level" then
            i = i + 1
            if i > #script_args then
                write_error("--log-level requires an argument")
                os.exit(1)
            end
            log_level = script_args[i]
        else
            table.insert(files, value)
        end
        i = i + 1
    end

    if #files == 0 then
        write_error("usage: tl run src/formatter/init.tl -- [--check] [--log-level <level>] <file...>")
        os.exit(1)
    end

    return Args.new(check_only, log_level, files)
end

-- Returns true if the file was changed (or would be changed in check mode).
local function process_file(path: string, check_only: boolean): boolean
    local source, read_err = read_file(path)
    if read_err then
        write_error("error reading %s: %s", path, read_err)
        os.exit(1)
    end

    local rewrite = rewriter.rewrite(source, path)

    if #rewrite.parse_errors > 0 then
        for _, err in ipairs(rewrite.parse_errors) do
            write_error("%s:%s:%s: %s", path, tostring(err.y), tostring(err.x), err.msg)
        end
        os.exit(1)
    end

    if not rewrite.changed then
        write_ok("%s: ok", path)
        return false
    end

    if check_only then
        write_ok("%s: would reformat", path)
        return true
    end

    local write_err = write_file(path, rewrite.output)
    if write_err then
        write_error("error writing %s: %s", path, write_err)
        os.exit(1)
    end
    write_ok("%s: reformatted", path)
    return true
end

local function main()
    local args = parse_args(arg)
    local ok_log_level = fmt_logger.set_level(args.log_level)
    if not ok_log_level then
        write_error("error, unknown log level: '%s'", args.log_level)
        os.exit(1)
    end

    local any_changed = false
    for _, path in ipairs(args.files) do
        if process_file(path, args.check_only) then
            any_changed = true
        end
    end

    if args.check_only and any_changed then
        os.exit(1)
    end
end

main()
