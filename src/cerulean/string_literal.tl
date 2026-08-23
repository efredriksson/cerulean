-- Source text of a string literal, rendered back out. Quote normalisation and
-- the long-bracket lookahead that decides whether a subscript needs a space --
-- both are about the literal's own characters, not about layout.
local ast = require("cerulean.ast")

local string_literal = {}

function string_literal.normalize_string_literal(
    tk: string, is_longstring: boolean
): string
    if is_longstring then
        return tk
    end
    local content = tk:sub(2, -2)
    if content:find('"', 1, true) then
        return tk
    end
    return '"' .. content .. '"'
end

function string_literal.key_starts_with_long_string(node: ast.Node): boolean
    -- When the key expression's leftmost token is a long string, the subscript `[`
    -- must be spaced away to prevent `[[[k]]` from being lexed as a long string.
    if node.is_longstring then
        return true
    end
    local descends_left = node.kind == "field"
        or node.kind == "method"
        or node.kind == "index"
        or node.kind == "call"
        or node.kind == "cast"
        or (node.kind == "op" and node.op.arity == 2)
    return descends_left and string_literal.key_starts_with_long_string(node.e1)
end

return string_literal
