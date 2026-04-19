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
    local self: Args = setmetatable({}, {__index = Args})
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
        write_error(
            "usage: tl run src/formatter/init.tl -- [--check] [--log-level <level>] <file...>"
        )
        os.exit(1)
    end

    return Args.new(check_only, log_level, files)
end

local function process_file(path: string, check_only: boolean): rewriter.Status
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

    if rewrite.status == "failed" then
        write_error("warning: %s: formatter failed, file left unchanged", path)
    end

    if rewrite.status == "unchanged" or rewrite.status == "failed" then
        return rewrite.status
    end

    if check_only then
        write_ok("%s: would reformat", path)
    else
        local write_err = write_file(path, rewrite.output)
        if write_err then
            write_error("error writing %s: %s", path, write_err)
            os.exit(1)
        end
        write_ok("%s: reformatted", path)
    end
    return rewrite.status
end

local function file_word(count: integer): string
    if count == 1 then
        return "1 file"
    end
    return tostring(count) .. " files"
end

local function formatted_word(check: boolean): string
    return check and "would be reformatted" or "reformatted"
end

local function format_summary(
    reformatted: integer, unchanged: integer, check_only: boolean
): string
    local reformatted_part = file_word(reformatted) .. " " .. formatted_word(check_only)
    local unchanged_part = file_word(unchanged) .. " left unchanged"

    if reformatted > 0 and unchanged > 0 then
        return reformatted_part .. ", " .. unchanged_part .. "."
    elseif reformatted > 0 then
        return reformatted_part .. "."
    elseif unchanged > 0 then
        return unchanged_part .. "."
    end
    return ""
end

local function main()
    local args = parse_args(arg)
    local ok_log_level = fmt_logger.set_level(args.log_level)
    if not ok_log_level then
        write_error("error, unknown log level: '%s'", args.log_level)
        os.exit(1)
    end

    local reformatted = 0
    local unchanged = 0
    local failed_format = 0

    for _, path in ipairs(args.files) do
        local status = process_file(path, args.check_only)
        if status == "failed" then
            failed_format = failed_format + 1
        elseif status == "reformatted" then
            reformatted = reformatted + 1
        else
            unchanged = unchanged + 1
        end
    end

    local summary = format_summary(reformatted, unchanged, args.check_only)
    if summary ~= "" then
        write_ok(summary)
    end
    if failed_format > 0 then
        write_error("%s failed to reformat.", file_word(failed_format))
    end

    if args.check_only and reformatted > 0 then
        os.exit(1)
    end
end

main()
