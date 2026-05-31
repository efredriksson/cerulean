local ast_traversal = require("cerulean.ast_traversal")
local doc = require("cerulean.doc")
local expr_doc = require("cerulean.expr_doc")
local fmt_logger = require("cerulean.fmt_logger")
local parser = require("cerulean.parser")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local source = require("cerulean.source")
local stmt_doc = require("cerulean.stmt_doc")

local type RenderContext = render_context.RenderContext

local block_doc = {}

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function verbatim_extent(
    stmt: parser.Node, block_dangling: {parser.Comment}
): integer
    local last = stmt.yend
    for _, comment in ipairs(stmt.trailing_comments or {}) do
        last = math.max(last, comment.yend)
    end
    for _, comment in ipairs(block_dangling) do
        if comment.y <= last then
            last = math.max(last, comment.yend)
        end
    end
    return last
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
        for _, comment in ipairs(candidate.leading_comments or {}) do
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

local function stmt_child_blocks(stmt: parser.Node): {parser.Node}
    local result: {parser.Node} = {}
    if stmt.body ~= nil then
        table.insert(result, stmt.body)
    end
    for _, if_block in ipairs(stmt.if_blocks or {}) do
        table.insert(result, if_block.body)
    end
    return result
end

local function stmt_child_surface_ranges(stmt: parser.Node): {source.Range}
    local result: {source.Range} = {}
    for _, child_block in ipairs(stmt_child_blocks(stmt)) do
        table.insert(result, block_surface_range(child_block))
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

    -- The own-range check above subtracts child blocks so an enclosing
    -- statement can stay structural while only its body is frozen. Structural
    -- rendering puts the enclosing `end` on the statement's closing line, which
    -- collides when a frozen child's verbatim text reaches that same line: the
    -- `end` would be emitted both verbatim and structurally. Freeze the whole
    -- statement so its source is emitted once.
    local last_line = max_source_line(stmt)
    for _, child_block in ipairs(stmt_child_blocks(stmt)) do
        for _, child in ipairs(child_block) do
            if
                max_source_line(child) == last_line
                and stmt_overlaps_fmt_off(child, fmt_off_regions)
            then
                return true
            end
        end
    end
    return false
end

local function collect_verbatim_lines(
    source_lines: {string},
    stmt: parser.Node,
    last_line: integer,
    previous_end: integer,
    previous_was_verbatim: boolean,
    fmt_off_regions: source.Regions,
    next_structural?: parser.Node
): {string}
    local first_line = stmt.y
    for _, comment in ipairs(stmt.leading_comments or {}) do
        if comment.y > previous_end and fmt_off_regions:includes_line(comment.y) then
            first_line = math.min(first_line, comment.y)
        end
    end
    local result: {string} = {}
    local shares_previous_line = first_line == previous_end
    local code_precedes_stmt = first_line == stmt.y
        and source_lines[first_line]:sub(1, stmt.x - 1):match("%S") ~= nil
    if shares_previous_line and previous_was_verbatim then
        -- The previous verbatim statement already emitted this shared line in
        -- full; skip it so it is not emitted twice.
        first_line = first_line + 1
    elseif shares_previous_line or code_precedes_stmt then
        -- Code before stmt.x on this line belongs to an already-rendered
        -- structural construct: either a previous sibling that ended here, or
        -- the enclosing statement whose header shares this line (e.g. a nested
        -- declaration). Emit only this statement's suffix so that prefix is not
        -- duplicated.
        --
        -- Exception: a multiline block comment whose opening is in the previous
        -- verbatim region but whose closing falls on this line. In that case
        -- the prefix is the closing delimiter (e.g. `]]`) which has not been
        -- emitted yet, so the full line must be included.
        local emit_full_line = false
        if code_precedes_stmt and not shares_previous_line then
            for _, comment in ipairs(stmt.leading_comments or {}) do
                if comment.y < first_line and comment.yend >= first_line then
                    emit_full_line = true
                    break
                end
            end
        end
        if emit_full_line then
            table.insert(result, source_lines[first_line])
        else
            table.insert(result, source_lines[first_line]:sub(stmt.x))
        end
        first_line = first_line + 1
    end

    first_line = math.max(first_line, previous_end + 1) -- clamp
    for line = first_line, last_line do
        table.insert(result, source_lines[line])
    end

    -- A following out-of-region statement may begin on this statement's last
    -- line (e.g. `end --[[c]] local type`). Stop the verbatim text before its
    -- first token so the structural pass can format it without duplication.
    if next_structural ~= nil and #result > 0 and next_structural.y == last_line then
        local truncated = (
            source_lines[last_line]:sub(1, next_structural.x - 1):gsub("%s+$", "")
        )
        if truncated == "" then
            table.remove(result)
        else
            result[#result] = truncated
        end
    end

    return result
end

local function blank_before_fmt_off_start(
    stmt: parser.Node, fmt_off_regions: source.Regions
): boolean
    for _, comment in ipairs(stmt.leading_comments or {}) do
        if fmt_off_regions:includes_line(comment.y) then
            return comment.blank_line_before
        end
    end
    return stmt.blank_line_before
end

local function render_block_doc(ctx: RenderContext, block: parser.Node): doc.Doc | nil
    local parts: {doc.Doc} = {}
    local previous_end: integer = 0
    local verbatim_boundary: integer = 0
    local line_before = false
    local previous_was_verbatim = false

    for idx, stmt in ipairs(block) do
        local overlaps = stmt_overlaps_fmt_off(stmt, ctx.fmt_off_regions)
        if overlaps then
            local pre_fmt_off: {parser.Comment} = {}
            for _, comment in ipairs(stmt.leading_comments or {}) do
                if not ctx.fmt_off_regions:includes_line(comment.y) then
                    table.insert(pre_fmt_off, comment)
                end
            end
            local next_stmt = block[idx + 1]
            local next_structural: parser.Node
            if
                next_stmt ~= nil
                and not stmt_overlaps_fmt_off(next_stmt, ctx.fmt_off_regions)
            then
                next_structural = next_stmt
            end
            local last_line = verbatim_extent(stmt, block.dangling_comments or {})
            local verbatim_lines = collect_verbatim_lines(
                ctx.source_lines,
                stmt,
                last_line,
                previous_end,
                previous_was_verbatim,
                ctx.fmt_off_regions,
                next_structural
            )
            if #pre_fmt_off > 0 or #verbatim_lines > 0 then
                line_before = render_builders.append_comment_docs(
                    parts, pre_fmt_off, line_before
                )
                if line_before then
                    table.insert(parts, doc.hardline())
                end
                if blank_before_fmt_off_start(stmt, ctx.fmt_off_regions) then
                    table.insert(parts, doc.hardline())
                end
                if #verbatim_lines > 0 then
                    table.insert(parts, doc.raw(verbatim_lines))
                end
            end
            previous_was_verbatim = true
            previous_end = last_line
            verbatim_boundary = last_line
        else
            line_before = render_builders.append_comment_docs(
                parts, stmt.leading_comments or {}, line_before
            )

            table.insert(
                parts,
                render_builders.append_lines_pre_node(
                    stmt, line_before, doc.stmt_sep_line()
                )
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
            previous_was_verbatim = false
            previous_end = stmt.yend
        end

        line_before = true
    end

    -- Dangling comments that fall inside a verbatim region were already emitted
    -- as raw source; skip them to avoid duplication. Comments that start after
    -- the last verbatim boundary are always included, even if they share a line
    -- with the last structural statement's yend.
    local dangling: {parser.Comment} = {}
    for _, comment in ipairs(block.dangling_comments or {}) do
        if comment.y > verbatim_boundary then
            table.insert(dangling, comment)
        end
    end
    render_builders.append_comment_docs(parts, dangling, line_before)

    return doc.concat(parts)
end

function block_doc.make_context(
    fmt_off_regions: source.Regions, source_lines: {string}
): RenderContext
    return render_context.RenderContext.new(
        render_block_doc, expr_doc.render, fmt_off_regions, source_lines
    )
end

function block_doc.render_block(
    ctx: RenderContext, block: parser.Node, max_width: integer, indent_width: integer
): string | nil
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

    local full_doc = doc.concat({get_prelude(), block_doc_node, doc.hardline()})
    fmt_logger.debug("doc IR:\n%s", full_doc)
    local rendered = full_doc:render(max_width, indent_width)
    fmt_logger.debug("render output:\n%s", rendered)
    return rendered
end

return block_doc
