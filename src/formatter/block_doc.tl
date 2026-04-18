local ast_traversal = require("formatter.ast_traversal")
local doc = require("formatter.doc")
local expr_doc = require("formatter.expr_doc")
local fmt_logger = require("formatter.fmt_logger")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local render_context = require("formatter.render_context")
local source = require("formatter.source")
local stmt_doc = require("formatter.stmt_doc")

local type RenderContext = render_context.RenderContext

local block_doc = {}

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function max_source_line(node: parser.Node): integer
    local max_line = node_end_line(node)
    ast_traversal.walk_descendants(
        node,
        function(child: parser.Node)
            local child_end = node_end_line(child)
            if child_end > max_line then
                max_line = child_end
            end
        end
    )
    return max_line
end

local function block_min_source_line(block: parser.Node): integer
    local min_line = block.y

    local function consider_comments(candidate: parser.Node)
        for _, comment in ipairs(candidate.comments or {}) do
            if comment.y < min_line then
                min_line = comment.y
            end
        end
    end

    consider_comments(block)
    ast_traversal.walk_descendants(block, consider_comments)
    return min_line
end

local function block_surface_range(block: parser.Node): source.Range
    return source.Range.new(block_min_source_line(block), max_source_line(block))
end

local function stmt_child_surface_ranges(stmt: parser.Node): {source.Range}
    local result: {source.Range} = {}
    if stmt.body ~= nil then
        table.insert(result, block_surface_range(stmt.body))
    end
    for _, if_block in ipairs(stmt.if_blocks or {}) do
        table.insert(result, block_surface_range(if_block))
    end
    return result
end

local function stmt_overlaps_fmt_off(
    stmt: parser.Node, fmt_off_regions: source.Regions
): boolean
    local stmt_range = source.Range.new(stmt.y, max_source_line(stmt))
    local own_ranges = source.subtract_many(
        {stmt_range}, stmt_child_surface_ranges(stmt)
    )
    for _, range in ipairs(own_ranges) do
        if fmt_off_regions:includes_range(range.first_line, range.last_line) then
            return true
        end
    end
    return false
end

local function collect_verbatim_lines(
    source_lines: {string}, stmt: parser.Node, previous_end: integer
): {string}
    local first_line = stmt.y
    for _, comment in ipairs(stmt.comments or {}) do
        if comment.y > previous_end then
            first_line = math.min(first_line, comment.y)
        end
    end
    local result: {string} = {}
    for line = first_line, stmt.yend do
        table.insert(result, source_lines[line] or "")
    end
    return result
end

local function blank_before_first_element(stmt: parser.Node): boolean
    local leading = stmt.comments or {}
    if #leading > 0 then
        return stmt.comments[1].blank_line_before
    end
    return stmt.blank_line_before
end

local function render_block_doc(ctx: RenderContext, block: parser.Node): doc.Doc | nil
    local parts: {doc.Doc} = {}
    local previous_end: integer = 0
    local line_before = false

    for _, stmt in ipairs(block) do
        if stmt_overlaps_fmt_off(stmt, ctx.fmt_off_regions) then
            if line_before then
                table.insert(parts, doc.hardline())
            end
            if blank_before_first_element(stmt) then
                table.insert(parts, doc.hardline())
            end
            local verbatim_lines = collect_verbatim_lines(
                ctx.source_lines, stmt, previous_end
            )
            table.insert(parts, doc.raw(verbatim_lines))
        else
            line_before = render_builders.append_comment_docs(
                parts, stmt.comments or {}, line_before
            )

            table.insert(
                parts,
                render_builders.append_lines_pre_node(stmt, line_before, doc.line())
            )
            local node_doc = stmt_doc.render_statement_doc(ctx, stmt)
            if node_doc is nil then
                fmt_logger.info(
                    "[structural] blocked at line %s: could not render doc for %s",
                    tostring(stmt.y),
                    stmt.kind
                )
                return nil
            end
            table.insert(parts, node_doc)
            table.insert(parts, render_builders.trailing_comment_doc(stmt))
        end

        previous_end = stmt.yend
        line_before = true
    end

    render_builders.append_comment_docs(parts, block.end_comments or {}, line_before)

    return doc.concat(parts)
end

function block_doc.make_context(
    fmt_off_regions: source.Regions, source_lines: {string}
): RenderContext
    return render_context.RenderContext.new(
        render_block_doc, expr_doc.render, fmt_off_regions, source_lines
    )
end

function block_doc.render_block(ctx: RenderContext, block: parser.Node): string | nil
    local block_doc_node = render_block_doc(ctx, block)
    if block_doc_node is nil then
        return nil
    end

    local function get_prelude(): doc.Doc
        if block.hashbang then
            return doc.concat({doc.text(block.hashbang), doc.hardline()})
        else
            return doc.text("")
        end
    end

    return doc.concat({get_prelude(), block_doc_node, doc.hardline()}):render(88, 4)
end

return block_doc
