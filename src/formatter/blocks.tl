local ast_utils = require("formatter.ast_utils")
local parser = require("formatter.parser")
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

function blocks.collect_from_ast(ast: parser.Node): {blocks.Block}
    local result: {blocks.Block} = {}
    for _, block_span in ipairs(ast_utils.collect_block_spans(ast)) do
        table.insert(
            result, blocks.Block.new(block_span.open_line, block_span.close_line)
        )
    end
    return result
end

function blocks.parse(source: string, filename: string): {blocks.Block}, {tl.Error}
    local ast, errs = parser.parse(source, filename)
    local result = blocks.collect_from_ast(ast)
    return result, errs
end

return blocks
