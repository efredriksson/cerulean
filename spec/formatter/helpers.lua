require("tl").loader()

local assert   = require("luassert")
local parser   = require("formatter.parser")
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

local function normalize_node(node)
    local normalized = {
        kind = node.kind,
    }

    if node.kind == "op" and node.op ~= nil then
        normalized.op = node.op.op
    end

    if node.kind == "identifier" or node.kind == "typeid" then
        normalized.tk = node.tk
    elseif node.kind == "string" then
        normalized.conststr = node.conststr or node.tk
    elseif node.kind == "integer" or node.kind == "number" then
        normalized.constnum = node.constnum or node.tk
    elseif node.kind == "boolean" or node.kind == "nil" then
        normalized.tk = node.tk
    end

    if node.attribute ~= nil then
        normalized.attribute = node.attribute
    end

    if node.key_parsed ~= nil then
        normalized.key_parsed = node.key_parsed
    end

    if node.is_method ~= nil then
        normalized.is_method = node.is_method
    end

    if node.hashbang ~= nil then
        normalized.hashbang = node.hashbang
    end

    local items = {}
    for _, child in ipairs(node) do
        table.insert(items, normalize_node(child))
    end
    if #items > 0 then
        normalized.items = items
    end

    local child_fields = {
        "body",
        "e1",
        "e2",
        "key",
        "value",
        "args",
        "name",
        "exp",
        "var",
        "from",
        "to",
        "step",
        "vars",
        "exps",
    }

    for _, field in ipairs(child_fields) do
        local child = node[field]
        if child ~= nil then
            normalized[field] = normalize_node(child)
        end
    end

    if node.if_blocks ~= nil then
        normalized.if_blocks = {}
        for _, block in ipairs(node.if_blocks) do
            table.insert(normalized.if_blocks, normalize_node(block))
        end
    end

    return normalized
end

local function assert_equivalent_ast_shape(before_source, after_source)
    local before_ast, before_errors = parser.parse(before_source, "before.tl")
    assert.same({}, before_errors)

    local after_ast, after_errors = parser.parse(after_source, "after.tl")
    assert.same({}, after_errors)

    assert.same(normalize_node(before_ast), normalize_node(after_ast))
end

local function assert_stable_rewrite(output, opts)
    local second_pass = rewriter.rewrite(output, "test.tl")
    assert.same({}, second_pass.parse_errors)
    assert.same(output, second_pass.output)
    assert.is_false(second_pass.changed)

    if not opts.skip_ast_equivalence then
        assert_equivalent_ast_shape(output, second_pass.output)
    end
end

-- Returns a test function that asserts the formatter rewrites input to expected.
function helpers.format(input, expected, opts)
    opts = opts or {}
    return function()
        local source = dedent(input)
        local expected_output = dedent(expected)
        local result = rewriter.rewrite(source, "test.tl")

        assert.same({}, result.parse_errors)
        assert.same(expected_output, result.output)
        assert.is_true(result.changed)

        if not opts.skip_ast_equivalence then
            assert_equivalent_ast_shape(source, result.output)
        end

        assert_stable_rewrite(result.output, opts)
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

-- Returns a test function that asserts the formatter leaves source unchanged.
function helpers.check(source, opts)
    opts = opts or {}
    return function()
        local dedented = dedent(source)
        local result = rewriter.rewrite(dedented, "test.tl")
        assert.same({}, result.parse_errors)
        assert.same(dedented, result.output)
        assert.is_false(result.changed)

        if not opts.skip_ast_equivalence then
            assert_equivalent_ast_shape(dedented, result.output)
        end

        assert_stable_rewrite(result.output, opts)
    end
end

return helpers
