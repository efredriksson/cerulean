-- AST traversal helpers and AST-derived source span collection.
local ast = require("cerulean.ast")
local source = require("cerulean.source")

local ast_traversal = {}

-- fmt: off
local BLOCK_NODE_KINDS: {ast.NodeKind: boolean} = {
    ["function"]             = true,
    ["function_declaration"] = true,
    ["local_macro"]          = true,
    ["if"]                   = true,
    ["while"]                = true,
    ["fornum"]               = true,
    ["forin"]                = true,
    ["repeat"]               = true,
    ["do"]                   = true,
    ["newtype"]              = true,
}

local FUNCTION_DEF_KINDS: {ast.NodeKind: boolean} = {
    ["function_declaration"] = true,
    ["local_macro"]          = true,
    ["function"]             = true,
}

-- fmt: on
function ast_traversal.is_block_node(node: ast.Node): boolean
    return BLOCK_NODE_KINDS[node.kind] ~= nil
end

function ast_traversal.is_function_def(node: ast.Node): boolean
    return FUNCTION_DEF_KINDS[node.kind] ~= nil
end

local function child_nodes(node: ast.Node): {ast.Node}
    local children: {ast.Node} = {}
    for _, child in ipairs(node) do
        table.insert(children, child)
    end
    -- Append each field individually: a list literal with nil holes would make
    -- ipairs stop at the first absent field, silently dropping the rest.
    local function add(child: ast.Node)
        if child ~= nil then
            table.insert(children, child)
        end
    end
    add(node.body)
    add(node.e1)
    add(node.e2)
    add(node.key)
    add(node.value)
    add(node.args)
    add(node.name)
    add(node.exp)
    add(node.var)
    add(node.from)
    add(node.to)
    add(node.step)
    add(node.vars)
    add(node.exps)
    add(node.macrodef)
    if node.if_blocks then
        for _, block in ipairs(node.if_blocks) do
            table.insert(children, block)
        end
    end
    return children
end

-- Pre-order walk of the comment-owning tree: every node and the types it holds,
-- a node before the types and children it holds, a type before its field entries
-- and member types, recursing through both so a container nested in type position
-- (a table in a record field's default, a record in an enum's type) is reached.
function ast_traversal.walk_owners(
    root: ast.Node, on_node: function(ast.Node), on_type: function(ast.Type)
)
    local visit_type: function(ast.Type)
    local visit_node: function(ast.Node)

    visit_type = function(typ: ast.Type)
        if typ == nil then
            return
        end
        on_type(typ)
        if typ is ast.RecordLikeType then
            for _, entry in ipairs(typ.field_entries) do
                visit_type(entry.the_type)
                if entry.node then
                    visit_node(entry.node)
                end
            end
            for _, iface in ipairs(typ.interface_list or {}) do
                visit_type(iface)
            end
            -- A record's `where` clause parks a FunctionType in meta_fields whose
            -- macroexp holds the clause; walk it like the rest.
            for _, meta in pairs(typ.meta_fields or {}) do
                visit_type(meta)
            end
            visit_type(typ.elements)
        elseif typ is ast.EnumType then
            for _, item in ipairs(typ.enum_items) do
                visit_node(item)
            end
        elseif typ is ast.GenericType then
            for _, ta in ipairs(typ.typeargs) do
                visit_type(ta)
            end
            visit_type(typ.t)
        elseif typ is ast.NominalType then
            for _, tv in ipairs(typ.typevals or {}) do
                visit_type(tv)
            end
        elseif typ is ast.ArrayType then
            visit_type(typ.elements)
        elseif typ is ast.MapType then
            visit_type(typ.keys)
            visit_type(typ.values)
        elseif typ is ast.FunctionType then
            visit_node(typ.args)
            visit_type(typ.rets)
            if typ.macroexp then
                visit_node(typ.macroexp.exp or typ.macroexp)
            end
        elseif typ is ast.TupleType then
            for _, t in ipairs(typ.tuple) do
                visit_type(t)
            end
        elseif typ is ast.AggregateType then
            for _, t in ipairs(typ.types) do
                visit_type(t)
            end
        elseif typ is ast.TypeArgType then
            visit_type(typ.constraint)
        end
    end

    visit_node = function(node: ast.Node)
        if node == nil then
            return
        end
        on_node(node)
        if node.def then
            visit_type(node.def)
        end
        if node.casttype then
            visit_type(node.casttype)
        end
        if node.argtype then
            visit_type(node.argtype)
        end
        if node.itemtype then
            visit_type(node.itemtype)
        end
        if node.decltuple then
            visit_type(node.decltuple)
        end
        if node.rets then
            visit_type(node.rets)
        end
        if node.typeargs then
            for _, ta in ipairs(node.typeargs) do
                visit_type(ta)
            end
        end
        if node.kind == "statements" then
            for _, stmt in ipairs(node) do
                visit_node(stmt)
            end
        else
            for _, child in ipairs(child_nodes(node)) do
                visit_node(child)
            end
        end
    end

    visit_node(root)
end

local function collect_block_ranges(nodes: {ast.Node}, result: {source.Range})
    for _, node in ipairs(nodes) do
        if ast_traversal.is_block_node(node) then
            table.insert(result, source.Range.new(node.y, node.yend))
        end

        collect_block_ranges(node.body and {node.body} or {}, result)
        collect_block_ranges(node.if_blocks or {}, result)
        collect_block_ranges(node, result)
    end
end

function ast_traversal.collect_block_ranges(root: ast.Node): {source.Range}
    local result: {source.Range} = {}
    collect_block_ranges(root, result)
    return result
end

return ast_traversal
