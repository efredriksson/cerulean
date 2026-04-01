local doc = require("formatter.doc")
local parser = require("formatter.parser")
local stmt_doc = require("formatter.stmt_doc")

local block_doc = {}

local type StatementRenderer = function(parser.Node): doc.Doc | nil

local function render_block_doc_with(
    block: parser.Node, render_statement: StatementRenderer
): doc.Doc | nil
    local parts: {doc.Doc} = {}

    for index, stmt in ipairs(block) do
        local stmt_doc_node = render_statement(stmt)
        if stmt_doc_node == nil then
            return nil
        end
        table.insert(parts, stmt_doc_node)
        if index < #block then
            table.insert(parts, doc.line(""))
        end
    end

    return doc.concat(parts)
end

function block_doc.render_block_doc(block: parser.Node): doc.Doc | nil
    local function render_statement(stmt: parser.Node): doc.Doc | nil
        return stmt_doc.render_statement_doc(stmt, block_doc.render_block_doc)
    end

    return render_block_doc_with(block, render_statement)
end

function block_doc.render_block(block: parser.Node): {string} | nil
    local block_doc_node = block_doc.render_block_doc(block)
    if block_doc_node == nil then
        return nil
    end
    local non_nil_block_doc_node = block_doc_node as doc.Doc

    return non_nil_block_doc_node:render(88, 0, 0, true)
end

return block_doc
