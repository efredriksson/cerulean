require("tl").loader()

local assert   = require("luassert")
local rewriter = require("formatter.rewriter")

local helpers = {}

-- Strips the common leading indentation from a [[...]] string so tests can
-- indent their inline source for readability without affecting the content.
local function dedent(s)
    s = s:gsub("^\n", "")
    local min_indent = math.huge
    for line in s:gmatch("[^\n]+") do
        local indent = #(line:match("^%s*"))
        if indent < min_indent then
            min_indent = indent
        end
    end
    if min_indent == math.huge then
        return s
    end
    local prefix = string.rep(" ", min_indent)
    local result = s:gsub("^" .. prefix, ""):gsub("\n" .. prefix, "\n")
    return (result:gsub("%s*$", "")) .. "\n"
end

-- Returns a test function that asserts the formatter rewrites input to expected.
function helpers.format(input, expected)
    return function()
        local result = rewriter.rewrite(dedent(input), "test.tl")
        assert.same(dedent(expected), result.output)
        assert.is_true(result.changed)
    end
end

-- Returns a test function that asserts the formatter reports parse errors
-- and leaves the source unchanged.
function helpers.parse_error(source)
    return function()
        local dedented = dedent(source)
        local result = rewriter.rewrite(dedented, "test.tl")
        assert.same(dedented, result.output)
        assert.is_false(result.changed)
        assert.is_true(#result.parse_errors > 0)
    end
end

-- Variants that take raw strings (no dedent) — useful for testing literal
-- whitespace characters such as tabs that dedent cannot handle correctly.
function helpers.format_raw(input, expected)
    return function()
        local result = rewriter.rewrite(input, "test.tl")
        assert.same(expected, result.output)
        assert.is_true(result.changed)
    end
end

function helpers.check_raw(source)
    return function()
        local result = rewriter.rewrite(source, "test.tl")
        assert.same(source, result.output)
        assert.is_false(result.changed)
    end
end

-- Returns a test function that asserts the formatter leaves source unchanged.
function helpers.check(source)
    return function()
        local dedented = dedent(source)
        local result = rewriter.rewrite(dedented, "test.tl")
        assert.same(dedented, result.output)
        assert.is_false(result.changed)
    end
end

return helpers
