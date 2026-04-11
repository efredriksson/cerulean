-- AST traversal helpers and AST-derived source span collection.
local parser = require("formatter.parser")
local source = require("formatter.source")

local ast_traversal = {}

-- fmt: off
local BLOCK_NODE_KINDS: {parser.NodeKind: boolean} = {
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

local FUNCTION_DEF_KINDS: {parser.NodeKind: boolean} = {
    ["local_function"]  = true,
    ["global_function"] = true,
    ["record_function"] = true,
    ["function"]        = true,
}

-- fmt: on
function ast_traversal.is_block_node(node: parser.Node): boolean
    return BLOCK_NODE_KINDS[node.kind] ~= nil
end

function ast_traversal.is_function_def(node: parser.Node): boolean
    return FUNCTION_DEF_KINDS[node.kind] ~= nil
end

function ast_traversal.walk_children(node: parser.Node, visit: function(parser.Node))
    for _, child in ipairs(node) do
        visit(child)
    end
    if node.body then
        visit(node.body)
    end
    if node.e1 then
        visit(node.e1)
    end
    if node.e2 then
        visit(node.e2)
    end
    if node.key then
        visit(node.key)
    end
    if node.value then
        visit(node.value)
    end
    if node.args then
        visit(node.args)
    end
    if node.name then
        visit(node.name)
    end
    if node.exp then
        visit(node.exp)
    end
    if node.var then
        visit(node.var)
    end
    if node.from then
        visit(node.from)
    end
    if node.to then
        visit(node.to)
    end
    if node.step then
        visit(node.step)
    end
    if node.vars then
        visit(node.vars)
    end
    if node.exps then
        visit(node.exps)
    end
    if node.if_blocks then
        for _, block in ipairs(node.if_blocks) do
            visit(block)
        end
    end
end

function ast_traversal.walk_descendants(node: parser.Node, visit: function(parser.Node))
    local function recurse(child: parser.Node)
        visit(child)
        ast_traversal.walk_descendants(child, visit)
    end

    ast_traversal.walk_children(node, recurse)
end

local function collect_block_ranges(nodes: {parser.Node}, result: {source.Range})
    for _, node in ipairs(nodes) do
        if ast_traversal.is_block_node(node) then
            table.insert(result, source.Range.new(node.y, node.yend))
        end

        collect_block_ranges(node.body and {node.body} or {}, result)
        collect_block_ranges(node.if_blocks or {}, result)
        collect_block_ranges(node, result)
    end
end

function ast_traversal.collect_block_ranges(ast: parser.Node): {source.Range}
    local result: {source.Range} = {}
    collect_block_ranges(ast, result)
    return result
end

function ast_traversal.has_multiline_descendant(node: parser.Node): boolean
    local found = false

    ast_traversal.walk_descendants(
        node,
        function(child: parser.Node)
            if not found and child.yend and child.yend > child.y then
                found = true
            end
        end
    )

    return found
end

return ast_traversal
