local fmt_logger = require("cerulean.fmt_logger")
local options = require("cerulean.options")
local rewriter = require("cerulean.rewriter")

local help_text = [[Usage: ceru [options] [files|dirs...]

  A formatter for Teal source code.

Options:
  --check                Check formatting; exit 1 if any file would be reformatted.
  --indent <n>           Indentation width (default: 4).
  --line-length <n>      Target line length (default: 88).
  --no-sort-requires     Disable sorting of require statements.
  --log-level <level>    Log level: nothing, info, debug (default: nothing).
  --help, -h             Show this help message.]]

local type FormatterOptions = options.FormatterOptions

local record Printer
    out: function(string)
    err: function(string)
end

local enum ProcessStatus
    "reformatted"
    "unchanged"
    "failed"
    "errored"
end

local cli = {Printer = Printer}

function cli.new_printer(out: function(string), err: function(string)): Printer
    return {out = out, err = err}
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

local function process_file(
    path: string, opts: FormatterOptions, printer: Printer
): ProcessStatus
    local source, read_err = read_file(path)
    if read_err then
        printer.err(string.format("error reading %s: %s", path, read_err))
        return "errored"
    end

    local rewrite = rewriter.rewrite(source, path, opts)

    if #rewrite.parse_errors > 0 then
        for _, err in ipairs(rewrite.parse_errors) do
            printer.err(
                string.format(
                    "%s:%s:%s: %s", path, tostring(err.y), tostring(err.x), err.msg
                )
            )
        end
        return "errored"
    end

    if rewrite.status == "failed" then
        printer.err(
            string.format("warning: %s: formatter failed, file left unchanged", path)
        )
        return "failed"
    end

    if rewrite.status == "unchanged" then
        return "unchanged"
    end

    if opts.check_only then
        printer.out(string.format("%s: would reformat", path))
    else
        local write_err = write_file(path, rewrite.output)
        if write_err then
            printer.err(string.format("error writing %s: %s", path, write_err))
            return "errored"
        end
        printer.out(string.format("%s: reformatted", path))
    end
    return "reformatted"
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

local function wants_help(args: {string}): boolean
    for _, value in ipairs(args) do
        if value == "--help" or value == "-h" then
            return true
        end
    end
    return false
end

function cli.run(args: {string}, printer: Printer): integer
    if wants_help(args) then
        printer.out(help_text)
        return 0
    end

    local opts, config_err = options.from_config_file_and_args(args)
    if config_err then
        printer.err(config_err)
        return 1
    end

    local ok_log_level = fmt_logger.set_level(opts.log_level)
    if not ok_log_level then
        printer.err(string.format("error, unknown log level: '%s'", opts.log_level))
        return 1
    end

    local reformatted = 0
    local unchanged = 0
    local failed_format = 0
    local errored = 0

    for _, path in ipairs(opts.files) do
        local status = process_file(path, opts, printer)
        if status == "failed" then
            failed_format = failed_format + 1
        elseif status == "reformatted" then
            reformatted = reformatted + 1
        elseif status == "errored" then
            errored = errored + 1
        else
            unchanged = unchanged + 1
        end
    end

    local summary = format_summary(reformatted, unchanged, opts.check_only)
    if summary ~= "" then
        printer.out(summary)
    end
    if failed_format > 0 then
        printer.err(string.format("%s failed to reformat.", file_word(failed_format)))
    end
    if errored > 0 then
        printer.err(string.format("%s could not be processed.", file_word(errored)))
    end

    if (opts.check_only and reformatted > 0) or errored > 0 or failed_format > 0 then
        return 1
    end
    return 0
end

return cli
