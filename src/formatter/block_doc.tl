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

-- Returns the last source line occupied by stmt, accounting for call args
-- that end on a line below the statement's own yend/y. This matters for
-- assignment statements (whose yend is nil) containing a call whose closing
-- paren carries a trailing_comment — without this, the trailing comment would
-- be misclassified as a leading comment of the next statement.
local function stmt_effective_end_line(stmt: parser.Node): integer
    local end_line = node_end_line(stmt)

    local function consider_call_exp(exp: parser.Node)
        if exp.kind == "op"
            and exp.op ~= nil
            and exp.op.op == "@funcall"
            and exp.e2 ~= nil
            and exp.e2.yend ~= nil
            and exp.e2.yend > end_line then
            end_line = exp.e2.yend
        end
    end

    if stmt.exps ~= nil then
        for _, exp in ipairs(stmt.exps) do
            consider_call_exp(exp)
        end
    end
    consider_call_exp(stmt)
    return end_line
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

    if block.unattached_comments ~= nil and #block.unattached_comments > 0 then
        for index, comment in ipairs(block.unattached_comments) do
            if index > 1 then
                table.insert(parts, doc.line(""))
            end
            if index > 1 and comment.blank_line_before then
                table.insert(parts, doc.line(""))
            end
            table.insert(parts, doc.text(comment.text))
        end
        if #block > 0 then
            table.insert(parts, doc.line(""))
        end
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
            local prev_end_line = stmt_effective_end_line(prev_stmt)
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

    if block.end_comments ~= nil and #block.end_comments > 0 then
        local previous_line = 0
        if #block > 0 then
            previous_line = stmt_effective_end_line(block[#block])
        end

        local line_broken = #block == 0
        for _, comment in ipairs(block.end_comments) do
            if comment.y == previous_line and #block > 0 then
                table.insert(parts, doc.text(" " .. comment.text))
                line_broken = false
            else
                if not line_broken then
                    table.insert(parts, doc.line(""))
                end
                if comment.y > previous_line + 1 then
                    table.insert(parts, doc.line(""))
                end
                table.insert(parts, doc.text(comment.text))
                line_broken = false
            end
            previous_line = comment.y
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
