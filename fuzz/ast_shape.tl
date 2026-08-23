-- Structural AST fingerprint for the fuzz loop: normalize a parse tree down to
-- the fields that carry program meaning, so classify() can detect a format pass
-- that changed what the code says (spec-side twin: normalize_node in
-- spec/cerulean/helpers.lua). Layout fields (positions, token spans, comments)
-- are deliberately absent.
local ast = require("cerulean.ast")

local record ShapeNode
    kind: string
    op: string
    tk: string
    conststr: string
    label: string
    attribute: string
    key_parsed: string
    is_method: boolean
    hashbang: string
    items: {ShapeNode}
    children: {string: ShapeNode}
    if_blocks: {ShapeNode}
    new: function(kind: string): ShapeNode
end

local record ast_shape
    normalize: function(node: ast.Node): ShapeNode
    equal: function(first: ShapeNode, second: ShapeNode): boolean
end

function ShapeNode.new(kind: string): ShapeNode
    local self: ShapeNode = setmetatable({}, {__index = ShapeNode})
    self.kind = kind
    return self
end

local function add_child(shape: ShapeNode, field_name: string, child: ast.Node)
    if child == nil then
        return
    end
    if shape.children == nil then
        shape.children = {}
    end
    shape.children[field_name] = ast_shape.normalize(child)
end

function ast_shape.normalize(node: ast.Node): ShapeNode
    local shape = ShapeNode.new(node.kind)

    if node.kind == "op" and node.op ~= nil then
        shape.op = node.op.op
    end

    if node.kind == "name" then
        shape.tk = node.tk
    elseif node.kind == "string" then
        shape.conststr = node.conststr or node.tk
    elseif
        node.kind == "integer"
        or node.kind == "number"
        or node.kind == "boolean"
        or node.kind == "nil"
    then
        shape.tk = node.tk
    elseif node.kind == "goto" or node.kind == "label" then
        shape.label = node.label
    end

    shape.attribute = node.attribute
    shape.key_parsed = node.key_parsed
    shape.is_method = node.is_method
    shape.hashbang = node.hashbang

    if #node > 0 then
        shape.items = {}
        for _, child in ipairs(node) do
            table.insert(shape.items, ast_shape.normalize(child))
        end
    end

    -- The single-child fields whose subtrees carry meaning; mirrors the
    -- spec-side normalize_node list.
    add_child(shape, "body", node.body)
    add_child(shape, "e1", node.e1)
    add_child(shape, "e2", node.e2)
    add_child(shape, "key", node.key)
    add_child(shape, "value", node.value)
    add_child(shape, "args", node.args)
    add_child(shape, "name", node.name)
    add_child(shape, "exp", node.exp)
    add_child(shape, "var", node.var)
    add_child(shape, "from", node.from)
    add_child(shape, "to", node.to)
    add_child(shape, "step", node.step)
    add_child(shape, "vars", node.vars)
    add_child(shape, "exps", node.exps)

    if node.if_blocks ~= nil then
        shape.if_blocks = {}
        for _, if_block in ipairs(node.if_blocks) do
            table.insert(shape.if_blocks, ast_shape.normalize(if_block))
        end
    end

    return shape
end

local function equal_lists(first: {ShapeNode}, second: {ShapeNode}): boolean
    if first == nil or second == nil then
        return first == second
    end
    if #first ~= #second then
        return false
    end
    for index = 1, #first do
        if not ast_shape.equal(first[index], second[index]) then
            return false
        end
    end
    return true
end

local function equal_children(
    first: {string: ShapeNode}, second: {string: ShapeNode}
): boolean
    if first == nil or second == nil then
        return first == second
    end
    for field_name, child in pairs(first) do
        if not ast_shape.equal(child, second[field_name]) then
            return false
        end
    end
    for field_name in pairs(second) do
        if first[field_name] == nil then
            return false
        end
    end
    return true
end

function ast_shape.equal(first: ShapeNode, second: ShapeNode): boolean
    if first == nil or second == nil then
        return first == second
    end
    return first.kind == second.kind
        and first.op == second.op
        and first.tk == second.tk
        and first.conststr == second.conststr
        and first.label == second.label
        and first.attribute == second.attribute
        and first.key_parsed == second.key_parsed
        and first.is_method == second.is_method
        and first.hashbang == second.hashbang
        and equal_lists(first.items, second.items)
        and equal_children(first.children, second.children)
        and equal_lists(first.if_blocks, second.if_blocks)
end

return ast_shape
