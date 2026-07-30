local daemon = require("cerulean.daemon")
local fmt_logger = require("cerulean.fmt_logger")
local options = require("cerulean.options")
local parser = require("cerulean.parser")
local rewriter = require("cerulean.rewriter")

local record DaemonStdIO is daemon.DaemonIO
end

function DaemonStdIO.new(): DaemonStdIO
    return setmetatable({}, {__index = DaemonStdIO})
end

function DaemonStdIO:read_line(): string
    return io.stdin:read("*l")
end

function DaemonStdIO:read_bytes(byte_count: integer): string
    return io.stdin:read(byte_count)
end

function DaemonStdIO:write(text: string)
    io.stdout:write(text)
end

function DaemonStdIO:write_err(text: string)
    io.stderr:write(text)
end

local help_text = [[Usage: ceru [options] [files|dirs...]

  A formatter for Teal source code.

Options:
  --check                Check formatting; exit 1 if any file would be reformatted.
  --indent <n>           Indentation width (default: 4).
  --line-length <n>      Target line length (default: 88).
  --no-sort-requires     Disable sorting of require statements.
  --log-level <level>    Log level: nothing, info, debug (default: nothing).
  -                      Read source from stdin, write formatted result to stdout.
  --help, -h             Show this help message.
  --version, -v          Print version and exit.]]

local version = "dev"

local type FormatterOptions = options.FormatterOptions

local record Stdio
    _write_stdout: function(string)
    _write_stderr: function(string)
    _read_stdin: function(): string
end

local enum ProcessStatus
    "reformatted"
    "unchanged"
    "failed"
    "errored"
end

local cli = {Stdio = Stdio}

function Stdio.new(
    write_stdout: function(string),
    write_stderr: function(string),
    read_stdin: function(): string
): Stdio
    local self: Stdio = setmetatable({}, {__index = Stdio})
    self._write_stdout = write_stdout
    self._write_stderr = write_stderr
    self._read_stdin = read_stdin
    return self
end

function Stdio:print(line: string)
    self._write_stdout(line .. "\n")
end

function Stdio:print_err(line: string)
    self._write_stderr(line .. "\n")
end

function Stdio:write(text: string)
    self._write_stdout(text)
end

function Stdio:read(): string
    return self._read_stdin()
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

local function report_parse_errors(
    stdio: Stdio, source_name: string, errors: {parser.Error}
)
    for _, err in ipairs(errors) do
        stdio:print_err(
            string.format(
                "%s:%s:%s: %s", source_name, tostring(err.y), tostring(err.x), err.msg
            )
        )
    end
end

local function process_file(
    path: string, opts: FormatterOptions, stdio: Stdio
): ProcessStatus
    local source, read_err = read_file(path)
    if read_err then
        stdio:print_err(string.format("error reading %s: %s", path, read_err))
        return "errored"
    end

    local rewrite = rewriter.rewrite(source, path, opts)

    if #rewrite.parse_errors > 0 then
        report_parse_errors(stdio, path, rewrite.parse_errors)
        return "errored"
    end

    if rewrite.status == "failed" then
        stdio:print_err(
            string.format(
                "%s: formatting skipped: %s; left unchanged",
                path,
                rewrite.failure_reason
            )
        )
        return "failed"
    end

    if rewrite.status == "unchanged" then
        return "unchanged"
    end

    if opts.check_only then
        stdio:print(string.format("%s: would reformat", path))
    else
        local write_err = write_file(path, rewrite.output)
        if write_err then
            stdio:print_err(string.format("error writing %s: %s", path, write_err))
            return "errored"
        end
        stdio:print(string.format("%s: reformatted", path))
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

local function args_contains(args: {string}, option: string): boolean
    for _, value in ipairs(args) do
        if value == ("--" .. option) or value == ("-" .. string.sub(option, 1, 1)) then
            return true
        end
    end
    return false
end

local function wants_help(args: {string}): boolean
    return args_contains(args, "help")
end

local function wants_version(args: {string}): boolean
    return args_contains(args, "version")
end

local function process_stdin(opts: FormatterOptions, stdio: Stdio): integer
    local source_name = "<stdin>"
    local rewrite = rewriter.rewrite(stdio:read(), source_name, opts)

    if #rewrite.parse_errors > 0 then
        report_parse_errors(stdio, source_name, rewrite.parse_errors)
        return 1
    end

    if rewrite.status == "failed" then
        stdio:print_err(string.format("%s: %s", source_name, rewrite.failure_reason))
        return 1
    end

    if opts.check_only then
        if rewrite.status == "reformatted" then
            return 1
        end
    else
        stdio:write(rewrite.output)
    end

    return 0
end

local function process_files(opts: FormatterOptions, stdio: Stdio): integer
    local reformatted = 0
    local unchanged = 0
    local failed_format = 0
    local errored = 0

    for _, path in ipairs(opts.files) do
        local status = process_file(path, opts, stdio)
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
        stdio:print(summary)
    end
    if failed_format > 0 then
        stdio:print_err(
            string.format("%s failed to reformat.", file_word(failed_format))
        )
    end
    if errored > 0 then
        stdio:print_err(string.format("%s could not be processed.", file_word(errored)))
    end

    if (opts.check_only and reformatted > 0) or errored > 0 or failed_format > 0 then
        return 1
    end
    return 0
end

function cli.run(args: {string}, stdio: Stdio): integer
    if args[1] == "daemon" then
        if wants_help(args) then
            stdio:print(daemon.help)
            return 0
        end

        io.stdout:setvbuf("no")
        io.stderr:setvbuf("no")
        daemon.run(DaemonStdIO.new())
        return 0
    end
    if wants_help(args) then
        stdio:print(help_text)
        return 0
    end
    if wants_version(args) then
        stdio:print(version)
        return 0
    end

    local opts, config_err = options.from_config_file_and_args(args)
    if config_err then
        stdio:print_err(config_err)
        return 1
    end

    local ok_log_level = fmt_logger.set_level(opts.log_level)
    if not ok_log_level then
        stdio:print_err(string.format("error, unknown log level: '%s'", opts.log_level))
        return 1
    end

    if opts.read_stdin then
        return process_stdin(opts, stdio)
    else
        return process_files(opts, stdio)
    end
end

return cli
