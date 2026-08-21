-- AST traversal helpers and AST-derived source span collection.
local parser = require("cerulean.parser")
local source = require("cerulean.source")

local ast_traversal = {}

-- fmt: off
local BLOCK_NODE_KINDS: {parser.NodeKind: boolean} = {
    ["function"]        = true,
    ["local_function"]  = true,
    ["local_macro"]     = true,
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
    ["local_macro"]     = true,
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

local function get_sub_nodes(node: parser.Node): {parser.Node}
    local sub_nodes: {parser.Node} = {}

    for _, child in ipairs(node) do
        table.insert(sub_nodes, child)
    end

    if node.body then
        table.insert(sub_nodes, node.body)
    end
    if node.e1 then
        table.insert(sub_nodes, node.e1)
    end
    if node.e2 then
        table.insert(sub_nodes, node.e2)
    end
    if node.key then
        table.insert(sub_nodes, node.key)
    end
    if node.value then
        table.insert(sub_nodes, node.value)
    end
    if node.args then
        table.insert(sub_nodes, node.args)
    end
    if node.name then
        table.insert(sub_nodes, node.name)
    end
    if node.exp then
        table.insert(sub_nodes, node.exp)
    end
    if node.var then
        table.insert(sub_nodes, node.var)
    end
    if node.from then
        table.insert(sub_nodes, node.from)
    end
    if node.to then
        table.insert(sub_nodes, node.to)
    end
    if node.step then
        table.insert(sub_nodes, node.step)
    end
    if node.vars then
        table.insert(sub_nodes, node.vars)
    end
    if node.exps then
        table.insert(sub_nodes, node.exps)
    end
    if node.if_blocks then
        for _, block in ipairs(node.if_blocks) do
            table.insert(sub_nodes, block)
        end
    end

    return sub_nodes
end

function ast_traversal.walk_descendants(node: parser.Node, visit: function(parser.Node))
    visit(node)

    for _, sub_node in ipairs(get_sub_nodes(node)) do
        ast_traversal.walk_descendants(sub_node, visit)
    end
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
