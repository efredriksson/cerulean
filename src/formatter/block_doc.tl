local doc = require("formatter.doc")
local fmt_logger = require("formatter.fmt_logger")
local parser = require("formatter.parser")
local stmt_doc = require("formatter.stmt_doc")
local structural_render_analysis = require("formatter.structural_render_analysis")

local type BlockLayout = structural_render_analysis.BlockLayout
local type StatementLayout = structural_render_analysis.StatementLayout

local block_doc = {}

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function classify_statement_comments(
    stmt: parser.Node, prev_stmt_end_line: integer
): {parser.Comment}, {parser.Comment}
    local trailing: {parser.Comment} = {}
    local leading: {parser.Comment} = {}
    if stmt.comments ~= nil then
        for _, comment in ipairs(stmt.comments) do
            if comment.y <= prev_stmt_end_line then
                table.insert(trailing, comment)
            else
                table.insert(leading, comment)
            end
        end
    end
    return trailing, leading
end

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

        if index == 1 then
            if stmt.comments ~= nil then
                for _, comment in ipairs(stmt.comments) do
                    if comment.y < stmt.y then
                        table.insert(parts, doc.text(comment.text))
                        table.insert(parts, doc.line(""))
                    end
                end
            end
        elseif index > 1 then
            local prev_stmt = block[index - 1]
            local prev_end_line = node_end_line(prev_stmt)
            local trailing_comments, leading_comments = classify_statement_comments(
                stmt, prev_end_line
            )

            for _, comment in ipairs(trailing_comments) do
                table.insert(parts, doc.text(" " .. comment.text))
            end

            table.insert(parts, doc.line(""))

            local prev_statement_layout: StatementLayout | nil = nil
            if not (typed_layout is nil) then
                local non_nil_layout = typed_layout
                prev_statement_layout = non_nil_layout.statements[index - 1]
            end
            if not (prev_statement_layout is nil) then
                local non_nil_prev_layout = prev_statement_layout
                if non_nil_prev_layout.preserve_blank_line_after then
                    table.insert(parts, doc.line(""))
                end
            end

            for _, comment in ipairs(leading_comments) do
                table.insert(parts, doc.text(comment.text))
                table.insert(parts, doc.line(""))
            end
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
