local parser = require("formatter.parser")
local tl = require("tl")

local record BlockSpan
    open_line: integer
    close_line: integer
end

local ast_utils = {
    BlockSpan = BlockSpan,
}

function BlockSpan.new(open_line: integer, close_line: integer): BlockSpan
    local self: BlockSpan = setmetatable({}, { __index = BlockSpan })
    self.open_line = open_line
    self.close_line = close_line
    return self
end

-- fmt: off
local BLOCK_NODE_KINDS: {tl.NodeKind: boolean} = {
    ["function"]        = true,
    ["local_function"]  = true,
    ["global_function"] = true,
    ["record_function"] = true,
    ["if"]              = true,
    ["while"]           = true,
    ["fornum"]          = true,
    ["forin"]           = true,
    ["repeat"]          = true,
    ["do"]              = true,
    ["newtype"]         = true,
}

local FUNCTION_DEF_KINDS: {tl.NodeKind: boolean} = {
    ["local_function"]  = true,
    ["global_function"] = true,
    ["record_function"] = true,
    ["function"]        = true,
}
-- fmt: on

function ast_utils.is_block_node(node: parser.Node): boolean
    return BLOCK_NODE_KINDS[node.kind] ~= nil
end

function ast_utils.is_function_def(node: parser.Node): boolean
    return FUNCTION_DEF_KINDS[node.kind] ~= nil
end

function ast_utils.walk_children(node: parser.Node, visit: function(parser.Node))
    for _, child in ipairs(node) do visit(child) end
    if node.body then visit(node.body) end
    if node.e1 then visit(node.e1) end
    if node.e2 then visit(node.e2) end
    if node.key then visit(node.key) end
    if node.value then visit(node.value) end
    if node.args then visit(node.args) end
    if node.name then visit(node.name) end
    if node.exp then visit(node.exp) end
    if node.var then visit(node.var) end
    if node.from then visit(node.from) end
    if node.to then visit(node.to) end
    if node.step then visit(node.step) end
    if node.vars then visit(node.vars) end
    if node.exps then visit(node.exps) end
    if node.if_blocks then
        for _, block in ipairs(node.if_blocks) do visit(block) end
    end
end

function ast_utils.walk_descendants(node: parser.Node, visit: function(parser.Node))
    local function recurse(child: parser.Node)
        visit(child)
        ast_utils.walk_descendants(child, visit)
    end

    ast_utils.walk_children(node, recurse)
end

local function collect_block_spans(nodes: {parser.Node}, result: {BlockSpan})
    for _, node in ipairs(nodes) do
        if ast_utils.is_block_node(node) then
            table.insert(result, BlockSpan.new(node.y, node.yend))
        end

        collect_block_spans(node.body and {node.body} or {}, result)
        collect_block_spans(node.if_blocks or {}, result)
        collect_block_spans(node, result)
    end
end

function ast_utils.collect_block_spans(ast: parser.Node): {BlockSpan}
    local result: {BlockSpan} = {}
    collect_block_spans(ast, result)
    return result
end

function ast_utils.find_enclosing_block_end(
    block_spans: {BlockSpan}, line: integer, last_line: integer
): integer
    local innermost_end = last_line + 1
    for _, block in ipairs(block_spans) do
        if block.open_line <= line and block.close_line > line then
            if block.close_line < innermost_end then
                innermost_end = block.close_line
            end
        end
    end
    return innermost_end
end

function ast_utils.collect_fmt_off_lines(
    source_lines: {string}, block_spans: {BlockSpan}
): {integer: boolean}
    local fmt_off_lines: {integer: boolean} = {}
    local formatting_off = false
    local off_start = 0
    local region_end = 0

    for line_number, line_str in ipairs(source_lines) do
        if not formatting_off and line_str:match("%-%-%s*fmt:%s*off") then
            formatting_off = true
            off_start = line_number
            region_end = ast_utils.find_enclosing_block_end(
                block_spans, line_number, #source_lines
            )
        end

        if formatting_off then
            if line_number >= region_end then
                formatting_off = false
            else
                fmt_off_lines[line_number] = true
                if line_number > off_start and line_str:match("%-%-%s*fmt:%s*on") then
                    formatting_off = false
                end
            end
        end
    end

    return fmt_off_lines
end

function ast_utils.has_multiline_descendant(node: parser.Node): boolean
    local found = false

    ast_utils.walk_descendants(node, function(child: parser.Node)
        if not found and child.yend and child.yend > child.y then
            found = true
        end
    end)

    return found
end

return ast_utils
