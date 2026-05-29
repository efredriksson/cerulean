-- Fuzz driver for the formatter. Run from repo root with grammarinator on PATH:
--   tl run fuzz/fuzz.tl
--   tl run fuzz/fuzz.tl -- --count 500
--   tl run fuzz/fuzz.tl -- --until-fail
--   tl run fuzz/fuzz.tl -- --until-fail --count 5000
--   tl run fuzz/fuzz.tl -- --kind crash,not_idempotent
--   tl run fuzz/fuzz.tl -- --trivia-rate 0.3
--   tl run fuzz/fuzz.tl -- --seed 42 --count 100
--   tl run fuzz/fuzz.tl -- --depth 30
-- Silent during the run; prints a summary at the end. Input parse errors are
-- counted as informational (grammar drift) and do not fail the run. On real
-- formatter findings, writes fuzz/regressions_spec.lua for debugging.
local options_module = require("cerulean.options")
local parser = require("cerulean.parser")
local rewriter = require("cerulean.rewriter")
local mutate = require("fuzz.mutate")

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
    formatted: string
    error: string
end

function Failure.new(
    kind: FailureKind, path: string, content: string, failure_error: string
): Failure
    local self: Failure = setmetatable({}, {__index = Failure})
    self.kind = kind
    self.path = path
    self.content = content
    self.formatted = ""
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
    trivia_rate: string
    seed: string
    depth: integer
    seed_corpus_dirs: {string}
    mutations_per_file: integer
end

function Config.new(): Config
    local self: Config = setmetatable({}, {__index = Config})
    self.has_kind_filter = false
    self.kinds = {}
    self.count = 1000
    self.until_fail = false
    self.trivia_rate = "0.3"
    self.seed = ""
    self.depth = 20
    self.seed_corpus_dirs = {}
    self.mutations_per_file = 5
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
        elseif flag == "--trivia-rate" then
            i = i + 1
            if i > #arg then
                io.stderr:write("fuzz: --trivia-rate requires an argument\n")
                os.exit(2)
            end
            local rate = tonumber(arg[i])
            if not rate or rate < 0 or rate > 1 then
                io.stderr:write("fuzz: --trivia-rate must be a number in [0,1]\n")
                os.exit(2)
            end
            config.trivia_rate = arg[i]
        elseif flag == "--seed" then
            i = i + 1
            if i > #arg then
                io.stderr:write("fuzz: --seed requires an argument\n")
                os.exit(2)
            end
            if not tonumber(arg[i]) then
                io.stderr:write("fuzz: --seed requires a number\n")
                os.exit(2)
            end
            config.seed = arg[i]
        elseif flag == "--depth" then
            i = i + 1
            if i > #arg then
                io.stderr:write("fuzz: --depth requires an argument\n")
                os.exit(2)
            end
            local d = tonumber(arg[i])
            if not d or d < 1 then
                io.stderr:write("fuzz: --depth must be a positive number\n")
                os.exit(2)
            end
            config.depth = math.floor(d)
        elseif flag == "--seed-corpus" then
            i = i + 1
            if i > #arg then
                io.stderr:write(
                    "fuzz: --seed-corpus requires a comma-separated dir list\n"
                )
                os.exit(2)
            end
            for dir in arg[i]:gmatch("[^,]+") do
                table.insert(config.seed_corpus_dirs, dir)
            end
        elseif flag == "--mutations-per-file" then
            i = i + 1
            if i > #arg then
                io.stderr:write("fuzz: --mutations-per-file requires an argument\n")
                os.exit(2)
            end
            local n = tonumber(arg[i])
            if not n or n < 0 then
                io.stderr:write(
                    "fuzz: --mutations-per-file must be a non-negative number\n"
                )
                os.exit(2)
            end
            config.mutations_per_file = math.floor(n)
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
local empty_skipped = 0

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
        local failure = Failure.new("not_idempotent", path, content, "")
        failure.formatted = result.output
        return failure
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
            local embedded_formatted = long_string_embed(failure.formatted)
            file:write(
                '    it("second format pass matches first: '
                    .. name
                    .. '", function()\n'
            )
            file:write(
                "        -- asserts formatter(original) == expected and formatter(expected) == expected\n"
            )
            file:write(
                "        helpers.format("
                    .. embedded
                    .. ", "
                    .. embedded_formatted
                    .. ", { skip_ast_equivalence = true })()\n"
            )
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
    io.stdout:write(string.format("Empty inputs (skipped): %d\n", empty_skipped))
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

local function check_grammarinator_installed()
    local ok = os.execute("grammarinator-process --version 2>/dev/null")
    if not ok then
        io.stderr:write(
            "fuzz: grammarinator not found on PATH; install with: pip install grammarinator\n"
        )
        os.exit(2)
    end
end

local function setup_generator()
    os.execute("mkdir -p fuzz/gen fuzz/corpus")
    local ok = os.execute(
        "grammarinator-process fuzz/Teal.g4 -o fuzz/gen/ --no-actions 2>/dev/null"
    )
    if not ok then
        io.stderr:write("fuzz: grammarinator-process failed\n")
        os.exit(1)
    end
end

local function generate_batch(config: Config, batch_size: integer): {string}
    local seed_arg = ""
    if config.seed ~= "" then
        seed_arg = " --random-seed " .. config.seed
    end
    local env_prefix = "FUZZ_TRIVIA_RATE=" .. config.trivia_rate
    if config.seed ~= "" then
        env_prefix = env_prefix .. " FUZZ_TRIVIA_SEED=" .. config.seed
    end
    local cmd = string.format(
        "%s grammarinator-generate TealGenerator.TealGenerator -r chunk -d %d -n %d -o fuzz/corpus/test_%%d.tl --sys-path fuzz/gen/ --sys-path fuzz/ -s serializer.trivia_serializer%s 2>/dev/null",
        env_prefix,
        config.depth,
        batch_size,
        seed_arg
    )
    local ok = os.execute(cmd)
    if not ok then
        io.stderr:write("fuzz: grammarinator-generate failed\n")
        os.exit(1)
    end
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
    if #content == 0 then
        empty_skipped = empty_skipped + 1
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

local function list_tl_files(dirs: {string}): {string}
    local paths: {string} = {}
    for _, dir in ipairs(dirs) do
        local handle = io.popen("find " .. dir .. " -name '*.tl' -type f 2>/dev/null")
        if handle then
            for line in handle:lines() do
                table.insert(paths, line)
            end
            handle:close()
        end
    end
    return paths
end

local function run_seed_corpus_mode(config: Config)
    local sources = list_tl_files(config.seed_corpus_dirs)
    if #sources == 0 then
        io.stderr:write("fuzz: --seed-corpus dirs contain no .tl files\n")
        os.exit(2)
    end
    local seed_int: integer | nil = nil
    if config.seed ~= "" then
        seed_int = math.floor(tonumber(config.seed) or 0)
    end
    local rng = mutate.Rng.new(seed_int)
    os.execute("mkdir -p fuzz/corpus")

    local target: integer
    if config.count == 0 then
        target = math.huge as integer
    else
        target = config.count
    end

    local i = 0
    while i < target do
        local source_path = sources[(i % #sources) + 1]
        local content = read_file(source_path)
        if content then
            local mutated = mutate.mutated(
                content, config.mutations_per_file, rng, source_path
            )
            local out_path = string.format("fuzz/corpus/mut_%d.tl", i % MAX_BATCH)
            local out_file = io.open(out_path, "w")
            if out_file then
                out_file:write(mutated)
                out_file:close()
                local should_stop = process_path(config, out_path)
                if should_stop then
                    return
                end
            end
        end
        i = i + 1
    end
end

local config = parse_args()

if #config.seed_corpus_dirs > 0 then
    run_seed_corpus_mode(config)
else
    check_grammarinator_installed()
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

        local paths = generate_batch(config, batch_size)
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
end

if config.until_fail and #failures == 0 then
    io.stdout:write(string.format("\nChecked %d samples, no issues found.\n", total))
    io.stdout:write(string.format("Empty inputs (skipped): %d\n", empty_skipped))
    io.stdout:write(string.format("Parse errors (ignored): %d\n", parse_error_count))
    os.exit(0)
end

print_summary(config)
os.exit(#failures == 0 and 0 or 1)
