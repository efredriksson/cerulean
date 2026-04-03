local doc = require("formatter.doc")
local fmt_logger = require("formatter.fmt_logger")
local parser = require("formatter.parser")
local stmt_doc = require("formatter.stmt_doc")
local structural_render_analysis = require("formatter.structural_render_analysis")

local type BlockLayout = structural_render_analysis.BlockLayout
local type StatementLayout = structural_render_analysis.StatementLayout

local block_doc = {}

local function render_block_doc_with(
    block: parser.Node, layout: BlockLayout
): doc.Doc | nil
    local parts: {doc.Doc} = {}
    local typed_layout: BlockLayout | nil = nil
    if not (layout is nil) then
        typed_layout = layout
    end

    for index, stmt in ipairs(block) do
        local statement_layout: StatementLayout | nil = nil
        if not (typed_layout is nil) then
            local non_nil_layout = typed_layout
            statement_layout = non_nil_layout.statements[index]
        end
        local stmt_doc_node = stmt_doc.render_statement_doc(
            stmt, render_block_doc_with, statement_layout
        )
        if stmt_doc_node is nil then
            fmt_logger.info(
                "[structural] blocked at line %s: could not render doc for %s",
                tostring(stmt.y),
                stmt.kind
            )
            return nil
        end
        table.insert(parts, stmt_doc_node)
        if index < #block then
            table.insert(parts, doc.line(""))
            if not (statement_layout is nil) then
                local non_nil_statement_layout = statement_layout
                if non_nil_statement_layout.preserve_blank_line_after then
                    table.insert(parts, doc.line(""))
                end
            end
        end
    end

    return doc.concat(parts)
end

function block_doc.render_block(block: parser.Node, layout: BlockLayout): {string} | nil
    local block_doc_node = render_block_doc_with(block, layout)
    if block_doc_node is nil then
        return nil
    end

    return block_doc_node:render(88, 0, 0, true)
end

return block_doc
