-- How tightly an expression node binds, and the parenthesization that follows
-- from it. The renderer rebuilds expressions from the AST rather than replaying
-- source text, so it must re-derive every parenthesis the grammar implies; this
-- module is the single place that knows operator binding strength.
local ast = require("cerulean.ast")

-- The cast keywords carry no `op` node, so their binding strength lives here
-- rather than on the parser's operator table: `as` binds tighter than every
-- operator, `is` binds with the relational ops.
local AS_PREC <const> = 50
local IS_PREC <const> = 3

local precedence = {}

function precedence.of_cast(node: ast.Node): integer
    if node.is_assertion then
        return IS_PREC
    end
    return AS_PREC
end

-- The binding strength of an operand, or 0 when nothing about the node binds:
-- leaves and suffix chains bind tighter than any operator, so they never take
-- parentheses from precedence alone.
function precedence.of_operand(node: ast.Node): integer
    if node.kind == "cast" then
        return precedence.of_cast(node)
    end
    if node.kind == "op" and node.op ~= nil and node.op.prec ~= nil then
        return node.op.prec
    end
    return 0
end

-- A unary operand needs parentheses when it binds looser than its parent. Only
-- the strict-less-than rule applies, so equal-precedence unary chains (`not not
-- x`) never take them.
function precedence.unary_operand_needs_parens(
    child: ast.Node, parent_prec: integer
): boolean
    local child_prec = precedence.of_operand(child)
    return child_prec > 0 and child_prec < parent_prec
end

-- Whether the renderer will wrap a binary operator's right operand in parens.
-- Narrower than unary_operand_needs_parens on purpose: only an `op` node is
-- considered, because a cast on the right of a binary operator renders bare and
-- so cannot rely on parentheses to fence off what follows it.
function precedence.binary_right_gets_parens(
    child: ast.Node, parent_prec: integer
): boolean
    if child.kind ~= "op" then
        return false
    end
    return child.op.prec < parent_prec
end

-- A control-flow head hangs its expression under the keyword when the
-- expression is headed by a binary operator or a cast: a long condition ending
-- in either breaks around the keyword rather than overflowing the line.
function precedence.is_operator_headed(node: ast.Node): boolean
    if node.kind == "cast" then
        return true
    end
    if node.kind ~= "op" or node.op == nil then
        return false
    end
    return node.op.arity == 2
end

return precedence
