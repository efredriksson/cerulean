local doc = require("formatter.doc")
local expr_doc = require("formatter.expr_doc")
local fmt_logger = require("formatter.fmt_logger")
local layout_types = require("formatter.layout_types")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local render_context = require("formatter.render_context")
local stmt_doc = require("formatter.stmt_doc")

local type BlockLayout = layout_types.BlockLayout
local type StatementLayout = layout_types.StatementLayout
local type RenderContext = render_context.RenderContext

local block_doc = {}

local function statement_is_verbatim(layout: StatementLayout | nil): boolean
    return not (layout is nil) and layout.render_mode == "verbatim"
end

local function render_verbatim(statement_layout: StatementLayout): doc.Doc
    local verbatim_lines = statement_layout.verbatim_lines
    if verbatim_lines is nil then
        assert(false, "Lines not setup correctly")
        return
    end
    return doc.raw(verbatim_lines)
end

local function render_block_doc_with(
    ctx: RenderContext, block: parser.Node, layout: BlockLayout
): doc.Doc | nil
    local line_items = render_builders.CommentLineItems.new()
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
        local stmt_is_verbatim = statement_is_verbatim(statement_layout)
        local stmt_doc_node: doc.Doc | nil = nil
        if stmt_is_verbatim and not (statement_layout is nil) then
            stmt_doc_node = render_verbatim(statement_layout)
        else
            stmt_doc_node = stmt_doc.render_statement_doc(ctx, stmt, statement_layout)
            if stmt_doc_node is nil then
                fmt_logger.info(
                    "[structural] blocked at line %s: could not render doc for %s",
                    tostring(stmt.y),
                    stmt.kind
                )
                return nil
            end
        end

        local comments: {parser.Comment} = {}
        if not stmt_is_verbatim then
            comments = stmt.comments or {}
        end

        local preserve_blank_line_after = false
        if not (statement_layout is nil) then
            preserve_blank_line_after = statement_layout.preserve_blank_line_after
        end

        line_items:add(
            stmt_doc_node,
            render_builders.statement_effective_end_line(stmt),
            comments,
            preserve_blank_line_after
        )
    end

    line_items:add_end_comments(block.end_comments or {})
    line_items:add_prefixed_comments(block.unattached_comments or {})

    local function entry_separator(
        sep_ctx: render_builders.EntrySeparatorContext
    ): doc.Doc
        if sep_ctx.previous_preserve_blank_line_after then
            if sep_ctx.next_starts_with_blank_line then
                return doc.line()
            end
            return doc.concat({doc.line(), doc.line()})
        end
        return doc.line()
    end

    return render_builders.render_line_entries(line_items, nil, entry_separator)
end

function block_doc.make_context(): RenderContext
    return render_context.RenderContext.new(
        render_block_doc_with, expr_doc.render, stmt_doc.render_statement_doc
    )
end

function block_doc.render_block(
    ctx: RenderContext, block: parser.Node, layout: BlockLayout
): {string} | nil
    local block_doc_node = render_block_doc_with(ctx, block, layout)
    if block_doc_node is nil then
        return nil
    end

    return block_doc_node:render(88, 0, 0, true)
end

return block_doc
