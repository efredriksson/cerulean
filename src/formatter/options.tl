-- CLI argument parsing: raw argv -> FormatterOptions domain object.
-- All user-facing formatter knobs live here; init.tl stays thin I/O orchestration.
local record FormatterOptions
    check_only: boolean
    log_level: string
    indent_width: integer
    max_line_width: integer
    sort_requires: boolean
    files: {string}
end

function FormatterOptions.new(
    check_only: boolean,
    log_level: string,
    indent_width: integer,
    max_line_width: integer,
    sort_requires: boolean,
    files: {string}
): FormatterOptions
    local self: FormatterOptions = setmetatable({}, {__index = FormatterOptions})
    self.check_only = check_only
    self.log_level = log_level
    self.indent_width = indent_width
    self.max_line_width = max_line_width
    self.sort_requires = sort_requires
    self.files = files
    return self
end

function FormatterOptions.default(): FormatterOptions
    return FormatterOptions.new(false, "nothing", 4, 88, true, {})
end

local function parse_positive_integer(raw: string, flag: string): integer, string
    local n = math.tointeger(tonumber(raw))
    if not n or n <= 0 then
        return nil, string.format("%s requires a positive integer, got '%s'", flag, raw)
    end
    return n, nil
end

function FormatterOptions.apply_args(
    options: FormatterOptions, script_args: {string}
): FormatterOptions, string
    local i = 1
    while i <= #script_args do
        local value = script_args[i]
        if value == "--check" then
            options.check_only = true
        elseif value == "--no-sort-requires" then
            options.sort_requires = false
        elseif value == "--log-level" then
            i = i + 1
            if i > #script_args then
                return nil, "--log-level requires an argument"
            end
            options.log_level = script_args[i]
        elseif value == "--indent" then
            i = i + 1
            if i > #script_args then
                return nil, "--indent requires an argument"
            end
            local n, err = parse_positive_integer(script_args[i], "--indent")
            if err then
                return nil, err
            end
            options.indent_width = n
        elseif value == "--line-length" then
            i = i + 1
            if i > #script_args then
                return nil, "--line-length requires an argument"
            end
            local n, err = parse_positive_integer(script_args[i], "--line-length")
            if err then
                return nil, err
            end
            options.max_line_width = n
        elseif value:sub(1, 2) == "--" then
            return nil, string.format("unknown flag: '%s'", value)
        else
            table.insert(options.files, value)
        end
        i = i + 1
    end

    if #options.files == 0 then
        return nil, "usage: tl run src/formatter/init.tl -- [--check] [--no-sort-requires] [--log-level <level>] [--indent <n>] [--line-length <n>] <file...>"
    end

    return options, nil
end

function FormatterOptions.from_args(script_args: {string}): FormatterOptions, string
    return FormatterOptions.apply_args(FormatterOptions.default(), script_args)
end

function FormatterOptions.from_config_file(): FormatterOptions, string
    local chunk, _load_err = loadfile("tlconfig.lua")
    if not chunk then
        return nil, nil
    end
    local config = chunk()
    if not (config is {any: any}) then
        return nil, "tlconfig.lua must return a table"
    end
    local formatter = config["formatter"]
    if not formatter then
        return nil, nil
    end
    if not (formatter is {any: any}) then
        return nil, "tlconfig.lua: 'formatter' must be a table"
    end
    local opts = FormatterOptions.default()

    local iw = formatter["indent_width"]
    if iw ~= nil then
        if not (iw is number) then
            return nil, "tlconfig.lua: formatter.indent_width must be a positive integer"
        end
        local n = math.tointeger(iw)
        if not n or n <= 0 then
            return nil, "tlconfig.lua: formatter.indent_width must be a positive integer"
        end
        opts.indent_width = n
    end

    local mlw = formatter["max_line_width"]
    if mlw ~= nil then
        if not (mlw is number) then
            return nil, "tlconfig.lua: formatter.max_line_width must be a positive integer"
        end
        local n = math.tointeger(mlw)
        if not n or n <= 0 then
            return nil, "tlconfig.lua: formatter.max_line_width must be a positive integer"
        end
        opts.max_line_width = n
    end

    local sr = formatter["sort_requires"]
    if sr ~= nil then
        if not (sr is boolean) then
            return nil, "tlconfig.lua: formatter.sort_requires must be a boolean"
        end
        opts.sort_requires = sr
    end

    return opts, nil
end

return FormatterOptions
