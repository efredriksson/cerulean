local tl = require("tl")

local record Block
    open_line: integer
    close_line: integer
end

local blocks = {Block = Block}

function Block.new(open_line: integer, close_line: integer): blocks.Block
    local self: blocks.Block = setmetatable({}, { __index = blocks.Block })
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
-- fmt: on

-- node.yend gives the exact closing line from the internal AST, so block
-- boundaries are precise regardless of blank lines before "end".
local function collect(nodes: {tl.Node}, result: {blocks.Block})
    for _, node in ipairs(nodes) do
        if BLOCK_NODE_KINDS[node.kind] then
            table.insert(result, blocks.Block.new(node.y, node.yend))
        end

        collect(node.body and {node.body} or {}, result)
        collect(node.if_blocks or {}, result)
        collect(node, result)
    end
end

local function combine_errors(
    lex_errors: {tl.Error},
    parse_errors: {tl.Error}
): {tl.Error}
    local combined: {tl.Error} = {}
    for _, err in ipairs(lex_errors) do table.insert(combined, err) end
    for _, err in ipairs(parse_errors) do table.insert(combined, err) end
    return combined
end

function blocks.parse(source: string, filename: string): {blocks.Block}, {tl.Error}
    local tokens, lex_errors = tl.lex(source, filename)
    local parse_errors: {tl.Error} = {}
    local ast, _ = tl.parse_program(tokens, parse_errors, filename)
    local result: {blocks.Block} = {}
    collect(ast, result)
    return result, combine_errors(lex_errors, parse_errors)
end

return blocks
