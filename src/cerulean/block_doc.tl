local ast = require("cerulean.ast")
local comment_slots = require("cerulean.comment_slots")
local doc = require("cerulean.doc")
local expr_doc = require("cerulean.expr_doc")
local fmt_logger = require("cerulean.fmt_logger")
local frozen_regions = require("cerulean.frozen_regions")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local source = require("cerulean.source")
local stmt_doc = require("cerulean.stmt_doc")
local token_stream = require("cerulean.token_stream")

local type RenderContext = render_context.RenderContext
local type Segment = frozen_regions.Segment

local block_doc = {}

-- One frozen run: any leading comments above the region render structurally,
-- then the run's source lines are emitted verbatim.
local function render_frozen_run_segment(
    ctx: RenderContext,
    block: ast.Node,
    segments: {Segment},
    idx: integer,
    parts: {doc.Doc},
    line_before: boolean
)
    local run = segments[idx].run
    local pre_fmt_off = frozen_regions.pre_region_leading_comments(ctx, run.first_stmt)
    local start_col = frozen_regions.run_start_col(ctx, run)
    local last_line_cut_col = frozen_regions.last_line_structural_col(
        block, run, segments, idx
    )
    local verbatim_lines = frozen_regions.collect_run_lines(
        ctx.source_lines, run, start_col, last_line_cut_col
    )
    -- The raw lines carry their comments already; mark them consumed so
    -- the enclosing statement's sweep does not relocate a copy.
    ctx.tokens:consume_slice(
        run.first_line, start_col, run.last_line, last_line_cut_col
    )
    if #pre_fmt_off == 0 and #verbatim_lines == 0 then
        return
    end
    line_before = render_builders.append_comment_docs(parts, pre_fmt_off, line_before)
    if line_before then
        table.insert(parts, doc.hardline())
    end
    if frozen_regions.blank_before_fmt_off_start(ctx, run.first_stmt) then
        table.insert(parts, doc.hardline())
    end
    if #verbatim_lines > 0 then
        table.insert(parts, doc.raw(verbatim_lines))
    end
end

-- One structural statement: its doc plus the comments the slots and the sweep
-- attach to it. False when the statement has no doc form, blocking the render.
local function render_structural_segment(
    ctx: RenderContext, stmt: ast.Node, parts: {doc.Doc}, line_before: boolean
): boolean
    -- Render first so the slot accessors mark their comments consumed; the
    -- sweep below then sees only the strays no slot took. leading and
    -- statement_trailing are read here too (each marks consumed) so the
    -- sweep runs strictly after every consuming read.
    local leading = ctx.slots:leading_comments(stmt)
    local node_doc = stmt_doc.render_statement_doc(ctx, stmt)
    if node_doc is nil then
        fmt_logger.info(
            "[structural] blocked at line %s: could not render doc for %s",
            tostring(stmt.y),
            stmt.kind
        )
        return false
    end
    local trailing = ctx.slots:statement_trailing_comments(stmt)
    -- Relocate comments stranded deep in the statement -- several at once,
    -- past what the slots and Stages A/B reached -- to its own-line leading,
    -- the only idempotent home for a multi-comment strand (the trailing slot
    -- joins comments on one line, which re-lexes as one). They join the
    -- leading run ahead of the pre-node separator, so each lands on its own
    -- line before the statement. Logging each preserves the make-fuzz signal
    -- the default-drop safe-skip would otherwise carry.
    local swept = ctx.slots:unconsumed_comments_in_span(stmt)
    for _, comment in ipairs(swept) do
        fmt_logger.info(
            "[sweep] relocated stranded comment at line %s: %s",
            tostring(comment.y),
            comment.text
        )
    end

    line_before = render_builders.append_comment_docs(parts, leading, line_before)
    line_before = render_builders.append_comment_docs(parts, swept, line_before)
    table.insert(
        parts,
        render_builders.append_lines_pre_node(stmt, line_before, doc.stmt_sep_line())
    )
    table.insert(parts, node_doc)
    table.insert(parts, render_builders.trailing_comment_doc(trailing))
    return true
end

local function render_block_doc(ctx: RenderContext, block: ast.Node): doc.Doc | nil
    local parts: {doc.Doc} = {}
    local verbatim_boundary: integer = 0
    local line_before = false

    local block_dangling = ctx.slots:dangling_comments(block)
    local segments = frozen_regions.group_segments(ctx, block, block_dangling)
    for idx, segment in ipairs(segments) do
        if segment.run ~= nil then
            render_frozen_run_segment(ctx, block, segments, idx, parts, line_before)
            verbatim_boundary = segment.run.last_line
        elseif not render_structural_segment(ctx, segment.stmt, parts, line_before) then
            return nil
        end
        line_before = true
    end

    -- Dangling comments that fall inside a verbatim region were already emitted
    -- as raw source; skip them to avoid duplication. Comments that start after
    -- the last verbatim boundary are always included, even if they share a line
    -- with the last structural statement's yend.
    local dangling: {ast.Comment} = {}
    for _, comment in ipairs(block_dangling) do
        if comment.y > verbatim_boundary then
            table.insert(dangling, comment)
        end
    end
    render_builders.append_comment_docs(parts, dangling, line_before)

    return doc.concat(parts)
end

function block_doc.make_context(
    fmt_off_regions: source.Regions,
    source_lines: {string},
    tokens: token_stream.Stream,
    leading_overrides: {ast.Node: {ast.Comment}}
): RenderContext
    return render_context.RenderContext.new(
        render_block_doc,
        expr_doc.render,
        fmt_off_regions,
        source_lines,
        tokens,
        comment_slots.CommentSlots.new(
            tokens, source_lines, fmt_off_regions, leading_overrides
        )
    )
end

function block_doc.render_block(
    ctx: RenderContext,
    block: ast.Node,
    max_width: integer,
    indent_width: integer,
    require_sort_tail: {ast.Comment}
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

    -- require_sort relocates own-line comments that float between sorted requires
    -- to the end of the block; they arrive here as a render-time tail since the
    -- block's own dangling comments now come from the token stream.
    local parts: {doc.Doc} = {get_prelude(), block_doc_node}
    render_builders.append_comment_docs(parts, require_sort_tail, true)
    table.insert(parts, doc.hardline())
    local full_doc = doc.concat(parts)
    fmt_logger.debug("doc IR:\n%s", full_doc)
    local rendered = full_doc:render(max_width, indent_width)
    fmt_logger.debug("render output:\n%s", rendered)
    return rendered
end

return block_doc
