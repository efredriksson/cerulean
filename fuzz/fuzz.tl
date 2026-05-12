-- Fuzz driver for the formatter. Run from repo root with grammarinator on PATH:
--   tl run fuzz/fuzz.tl
--   tl run fuzz/fuzz.tl -- --count 500
--   tl run fuzz/fuzz.tl -- --until-fail
--   tl run fuzz/fuzz.tl -- --until-fail --count 5000
--   tl run fuzz/fuzz.tl -- --kind crash,not_idempotent
-- Silent during the run; prints a summary at the end. Input parse errors are
-- counted as informational (grammar drift) and do not fail the run. On real
-- formatter findings, writes fuzz/regressions_spec.lua for debugging.
local options_module = require("cerulean.options")
local parser = require("cerulean.parser")
local rewriter = require("cerulean.rewriter")

local function read_file(path: string): string | nil
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Finds the minimum = level so the content can be embedded in a Lua long string.
-- Avoids two pitfalls: the closer ']=*]' appearing inside content, and content
-- ending with ']' followed by exactly N '='s, which would fuse with the closer.
local function long_string_embed(content: string): string
    local level = 0
    local function is_unsafe(lv: integer): boolean
        local eq = string.rep("=", lv)
        if content:find("]" .. eq .. "]", 1, true) then
            return true
        end
        if content:sub(-(lv + 1)) == "]" .. eq then
            return true
        end
        return false
    end
    while is_unsafe(level) do
        level = level + 1
    end
    local eq = string.rep("=", level)
    return "[" .. eq .. "[" .. content .. "]" .. eq .. "]"
end

local function format_parse_errors(errors: {parser.Error}): string
    local lines: {string} = {}
    for _, parse_error in ipairs(errors) do
        table.insert(
            lines,
            string.format(
                "%s:%d:%d: %s",
                parse_error.filename,
                parse_error.y,
                parse_error.x,
                parse_error.msg
            )
        )
    end
    return table.concat(lines, "\n")
end

local enum FailureKind
    "crash"
    "render_failed"
    "broken_output"
    "not_idempotent"
end

local record Failure
    kind: FailureKind
    path: string
    content: string
    error: string
end

function Failure.new(
    kind: FailureKind, path: string, content: string, failure_error: string
): Failure
    local self: Failure = setmetatable({}, {__index = Failure})
    self.kind = kind
    self.path = path
    self.content = content
    self.error = failure_error
    return self
end

local valid_kinds: {string: FailureKind} = {
    crash = "crash",
    render_failed = "render_failed",
    broken_output = "broken_output",
    not_idempotent = "not_idempotent",
}

local record Config
    has_kind_filter: boolean
    kinds: {FailureKind: boolean}
    count: integer
    until_fail: boolean
end

function Config.new(): Config
    local self: Config = setmetatable({}, {__index = Config})
    self.has_kind_filter = false
    self.kinds = {}
    self.count = 1000
    self.until_fail = false
    return self
end

local function parse_args(): Config
    local config = Config.new()
    local has_explicit_count = false
    local i = 1
    while i <= #arg do
        local flag = arg[i]
        if flag == "--kind" then
            i = i + 1
            if i > #arg then
                io.stderr:write("fuzz: --kind requires an argument\n")
                os.exit(2)
            end
            config.has_kind_filter = true
            for word in arg[i]:gmatch("[^,]+") do
                local kind = valid_kinds[word]
                if not kind then
                    io.stderr:write("fuzz: unknown kind: " .. word .. "\n")
                    os.exit(2)
                end
                config.kinds[kind] = true
            end
        elseif flag == "--count" then
            i = i + 1
            if i > #arg then
                io.stderr:write("fuzz: --count requires an argument\n")
                os.exit(2)
            end
            local n = tonumber(arg[i])
            if not n then
                io.stderr:write("fuzz: --count requires a number\n")
                os.exit(2)
            end
            config.count = math.floor(n)
            has_explicit_count = true
        elseif flag == "--until-fail" then
            config.until_fail = true
        else
            io.stderr:write("fuzz: unknown flag: " .. flag .. "\n")
            os.exit(2)
        end
        i = i + 1
    end
    if config.until_fail and not has_explicit_count then
        config.count = 0
    end
    return config
end

local function is_wanted(kind: FailureKind, config: Config): boolean
    if not config.has_kind_filter then
        return true
    end
    return config.kinds[kind] == true
end

local failures: {Failure} = {}
local total = 0
local parse_error_count = 0

-- Returns a Failure (formatter-side issue) or nil. Input parse errors bump
-- parse_error_count and return nil — they're grammar drift, not formatter bugs.
local function classify(path: string, content: string): Failure | nil
    local opts = options_module.default()
    local ok, result = pcall(rewriter.rewrite, content, path, opts)
    if not ok then
        return Failure.new("crash", path, content, tostring(result))
    end
    if #result.parse_errors > 0 then
        parse_error_count = parse_error_count + 1
        return nil
    end
    if result.status == "failed" then
        return Failure.new("render_failed", path, content, "")
    end

    local ok2, result2 = pcall(rewriter.rewrite, result.output, path, opts)
    if not ok2 then
        return Failure.new(
            "crash", path, result.output, "second pass: " .. tostring(result2)
        )
    end
    if #result2.parse_errors > 0 then
        return Failure.new(
            "broken_output", path, content, format_parse_errors(result2.parse_errors)
        )
    end
    if result2.status == "failed" then
        return Failure.new("render_failed", path, result.output, "")
    end
    if result2.output ~= result.output then
        return Failure.new("not_idempotent", path, result.output, "")
    end
    return nil
end

local kind_order: {FailureKind} = {
    "not_idempotent", "render_failed", "broken_output", "crash"
}

local function counts_by_kind(): {FailureKind: integer}
    local counts: {FailureKind: integer} = {
        crash = 0,
        broken_output = 0,
        not_idempotent = 0,
        render_failed = 0,
    }
    for _, failure in ipairs(failures) do
        counts[failure.kind] = counts[failure.kind] + 1
    end
    return counts
end

local function group_by_kind(): {FailureKind: {Failure}}
    local groups: {FailureKind: {Failure}} = {
        crash = {},
        broken_output = {},
        not_idempotent = {},
        render_failed = {},
    }
    for _, failure in ipairs(failures) do
        table.insert(groups[failure.kind], failure)
    end
    return groups
end

local function first_line(text: string): string
    return text:match("^[^\n]*") or ""
end

local function write_regression_spec(): string
    local spec_path = "fuzz/regressions_spec.lua"
    local file = assert(io.open(spec_path, "w"))

    file:write("-- Generated by fuzz/fuzz.tl. Do not commit.\n")
    file:write("-- Run: busted fuzz/regressions_spec.lua\n\n")
    file:write('require("tl").loader()\n')
    file:write('local rewriter = require("cerulean.rewriter")\n')
    file:write('local options_module = require("cerulean.options")\n')
    file:write('local helpers = require("spec.cerulean.helpers")\n\n')
    file:write('describe("fuzz regressions", function()\n\n')

    for _, failure in ipairs(failures) do
        local match_result = failure.path:match("([^/]+%.tl)$")
        local name = match_result or failure.path
        local embedded = long_string_embed(failure.content)

        if failure.kind == "crash" then
            file:write("    -- " .. failure.error:gsub("\n", "\n    -- ") .. "\n")
            file:write('    it("does not crash: ' .. name .. '", function()\n')
            file:write(
                "        rewriter.rewrite("
                    .. embedded
                    .. ', "test.tl", options_module.default())\n'
            )
            file:write("    end)\n\n")
        elseif failure.kind == "render_failed" then
            file:write('    it("renders without failure: ' .. name .. '", function()\n')
            file:write(
                "        local result = rewriter.rewrite("
                    .. embedded
                    .. ', "test.tl", options_module.default())\n'
            )
            file:write('        assert.are_not.equal("failed", result.status)\n')
            file:write("    end)\n\n")
        elseif failure.kind == "broken_output" then
            file:write("    -- " .. failure.error:gsub("\n", "\n    -- ") .. "\n")
            file:write(
                '    it("produces parseable output: ' .. name .. '", function()\n'
            )
            file:write(
                "        local result = rewriter.rewrite("
                    .. embedded
                    .. ', "test.tl", options_module.default())\n'
            )
            file:write(
                '        local result2 = rewriter.rewrite(result.output, "test.tl", options_module.default())\n'
            )
            file:write("        assert.same({}, result2.parse_errors)\n")
            file:write("    end)\n\n")
        elseif failure.kind == "not_idempotent" then
            file:write('    it("is idempotent: ' .. name .. '", function()\n')
            file:write("        helpers.check(" .. embedded .. ")()\n")
            file:write("    end)\n\n")
        end
    end

    file:write("end)\n")
    file:close()
    return spec_path
end

local function print_summary(config: Config)
    io.stdout:write("\n")
    local groups = group_by_kind()
    for _, kind in ipairs(kind_order) do
        local group = groups[kind]
        if #group > 0 then
            io.stdout:write(kind .. ":\n")
            for _, failure in ipairs(group) do
                io.stdout:write("  " .. failure.path .. "\n")
                if failure.error ~= "" then
                    io.stdout:write("      " .. first_line(failure.error) .. "\n")
                end
            end
        end
    end

    io.stdout:write("\n")
    io.stdout:write(string.format("Fuzzed %d inputs.\n", total))
    io.stdout:write(string.format("Parse errors (ignored): %d\n\n", parse_error_count))

    local counts = counts_by_kind()
    if config.has_kind_filter then
        local kind_names: {string} = {}
        for _, kind in ipairs(kind_order) do
            if config.kinds[kind] then
                table.insert(kind_names, kind)
            end
        end
        io.stdout:write(
            string.format(
                "Formatter findings (filtered to: %s): %d\n",
                table.concat(kind_names, ", "),
                #failures
            )
        )
    else
        io.stdout:write(string.format("Formatter findings: %d\n", #failures))
    end
    for _, kind in ipairs(kind_order) do
        io.stdout:write(string.format("    %-15s %d\n", kind .. ":", counts[kind]))
    end
    io.stdout:write("\n")

    if #failures > 0 then
        local spec_path = write_regression_spec()
        io.stdout:write("\nRegression spec: busted " .. spec_path .. "\n")
    end
end

local MAX_BATCH = 1000

local function setup_generator()
    os.execute("mkdir -p fuzz/gen fuzz/corpus")
    os.execute(
        "grammarinator-process fuzz/Teal.g4 -o fuzz/gen/ --no-actions 2>/dev/null"
    )
end

local function generate_batch(batch_size: integer): {string}
    os.execute(
        string.format(
            "grammarinator-generate TealGenerator.TealGenerator -r chunk -d 20 -n %d -o fuzz/corpus/test_%%d.tl --sys-path fuzz/gen/ -s grammarinator.runtime.serializer.simple_space_serializer 2>/dev/null",
            batch_size
        )
    )
    local paths: {string} = {}
    for i = 0, batch_size - 1 do
        table.insert(paths, string.format("fuzz/corpus/test_%d.tl", i))
    end
    return paths
end

local function process_path(config: Config, path: string): boolean
    total = total + 1
    local content = read_file(path)
    if not content then
        local failure = Failure.new("crash", path, "", "could not read file")
        if is_wanted(failure.kind, config) then
            table.insert(failures, failure)
            return config.until_fail
        end
        return false
    end
    local failure = classify(path, content)
    if failure is nil then
        return false
    end
    if is_wanted(failure.kind, config) then
        table.insert(failures, failure)
        return config.until_fail
    end
    return false
end

local config = parse_args()
setup_generator()

local generated_total = 0
local done = false
while not done do
    local batch_size: integer
    if config.count == 0 then
        batch_size = MAX_BATCH
    else
        batch_size = math.min(MAX_BATCH, config.count - generated_total)
        if batch_size <= 0 then
            break
        end
    end

    local paths = generate_batch(batch_size)
    generated_total = generated_total + batch_size

    for _, path in ipairs(paths) do
        local should_stop = process_path(config, path)
        if should_stop then
            done = true
            break
        end
    end

    if not done then
        if config.count > 0 and generated_total >= config.count then
            done = true
        end
    end
end

if config.until_fail and #failures == 0 then
    io.stdout:write(string.format("\nChecked %d samples, no issues found.\n", total))
    io.stdout:write(string.format("Parse errors (ignored): %d\n", parse_error_count))
    os.exit(0)
end

print_summary(config)
os.exit(#failures == 0 and 0 or 1)
