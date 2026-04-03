-- Block of AST statements → doc.Doc (render_block_doc) or {string} (render_block).
-- Recursively renders each statement via stmt_doc; returns nil if any statement is unsupported.
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local stmt_doc = require("formatter.stmt_doc")

local block_doc = {}

local interface StatementLayout
    preserve_blank_line_after: boolean
    body_layout: any
    if_block_layouts: {any} | nil
end

local interface BlockLayout
    statements: {StatementLayout}
end

local type StatementRenderer = function(parser.Node, StatementLayout | nil): doc.Doc | nil

local function render_block_doc_with(
    block: parser.Node, render_statement: StatementRenderer, layout: any
): doc.Doc | nil
    local parts: {doc.Doc} = {}
    local typed_layout: BlockLayout | nil = nil
    if layout ~= nil then
        typed_layout = layout as BlockLayout
    end

    for index, stmt in ipairs(block) do
        local statement_layout: StatementLayout | nil = nil
        if typed_layout ~= nil then
            local non_nil_layout = typed_layout as BlockLayout
            statement_layout = non_nil_layout.statements[index]
        end
        local stmt_doc_node = render_statement(stmt, statement_layout)
        if stmt_doc_node == nil then
            return nil
        end
        table.insert(parts, stmt_doc_node)
        if index < #block then
            table.insert(parts, doc.line(""))
            if statement_layout ~= nil then
                local non_nil_statement_layout = statement_layout as StatementLayout
                if non_nil_statement_layout.preserve_blank_line_after then
                    table.insert(parts, doc.line(""))
                end
            end
        end
    end

    return doc.concat(parts)
end

function block_doc.render_block_doc(block: parser.Node, layout: any): doc.Doc | nil
    local function render_statement(
        stmt: parser.Node, statement_layout: StatementLayout | nil
    ): doc.Doc | nil
        return stmt_doc.render_statement_doc(
            stmt, block_doc.render_block_doc, statement_layout
        )
    end

    return render_block_doc_with(block, render_statement, layout)
end

function block_doc.render_block(block: parser.Node, layout: any): {string} | nil
    local block_doc_node = block_doc.render_block_doc(block, layout)
    if block_doc_node == nil then
        return nil
    end
    local non_nil_block_doc_node = block_doc_node as doc.Doc

    return non_nil_block_doc_node:render(88, 0, 0, true)
end

return block_doc
