local ast = require("cerulean.ast")
local comment_slots = require("cerulean.comment_slots")
local doc = require("cerulean.doc")
local expr_doc = require("cerulean.expr_doc")
local fmt_logger = require("cerulean.fmt_logger")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local source = require("cerulean.source")
local stmt_doc = require("cerulean.stmt_doc")
local token_stream = require("cerulean.token_stream")

local type RenderContext = render_context.RenderContext

local block_doc = {}

-- Last source line the node's text reaches. Token end lines never decrease with
-- token index -- token k+1 starts at or after the line token k ends on -- so the
-- span's furthest line is read off its last token; no descendant walk. A
-- statement's own `yend` can reach one line further: the parser deletes a
-- consumed trailing `;` from the token array but keeps its line in yend, and
-- fmt:off geometry must still reach it (a region anchored only by the `;`
-- line must freeze the statement). Trailing comments past the last token are
-- the node's own trailing read; a statements block carries no trailing of its
-- own (its inner comments are its statements' or its dangling, the latter
-- sitting before the closer and so within the span), so that read is skipped.
local function max_source_line(ctx: RenderContext, node: ast.Node): integer
    if node.tok_last == nil or #ctx.tokens == 0 then
        return node.yend or 0
    end
    local last = ctx.tokens[node.tok_last].yend
    last = math.max(last, node.yend)
    if node.kind ~= "statements" then
        last = math.max(last, ctx.slots:trailing_extent(node))
    end
    return last
end

local function verbatim_extent(
    ctx: RenderContext, stmt: ast.Node, block_dangling: {ast.Comment}
): integer
    -- verbatime needs to include any dangling comments
    -- for enclosing block that overlap with statement
    local last = max_source_line(ctx, stmt)
    for _, comment in ipairs(block_dangling) do
        if comment.y <= last then
            last = math.max(last, comment.yend)
        end
    end
    return last
end

-- First source line the block's text reaches, counting leading comments.
-- Comments attach to tokens in source order: only a leading comment can sit
-- above the block's own first line, and the earliest one leads the block's first
-- statement -- deeper descendants live on later tokens. A statements block has
-- no leading of its own (reading it would resolve to the closer token and pull
-- the dangling in), so an empty block is just its own line.
local function block_min_source_line(ctx: RenderContext, block: ast.Node): integer
    local min_line = block.y
    local first = block[1]
    if first ~= nil and first.kind ~= "statements" then
        for _, comment in ipairs(ctx.slots:leading_comments(first)) do
            if comment.y < min_line then
                min_line = comment.y
            end
        end
    end
    return min_line
end

-- The token before a block's first is what opened it: `do`, `then`, `else`,
-- `repeat`, or the last token of a signature. Zero when there is none to read,
-- leaving the clamp below a no-op.
local function block_opener_line(ctx: RenderContext, block: ast.Node): integer
    if block.tok_first == nil or block.tok_first < 2 or #ctx.tokens == 0 then
        return 0
    end
    return ctx.tokens[block.tok_first - 1].y
end

-- The lines a block covers on its own, or nil when it covers none. A line the
-- block shares with its opener or closer (`do --[[c]] x = 1`, `x = 1 end`)
-- belongs to the enclosing statement: a block claiming it would subtract that
-- line from the statement's own ranges, hiding the statement's own frozen text
-- from the fmt:off check.
local function block_surface_range(ctx: RenderContext, block: ast.Node): source.Range
    local first_line = math.max(
        block_min_source_line(ctx, block), block_opener_line(ctx, block) + 1
    )
    local last_line = math.min(max_source_line(ctx, block), block.yend - 1)
    if last_line < first_line then
        return nil
    end
    return source.Range.new(first_line, last_line)
end

local function stmt_child_blocks(stmt: ast.Node): {ast.Node}
    local result: {ast.Node} = {}
    if stmt.body ~= nil then
        table.insert(result, stmt.body)
    end
    for _, if_block in ipairs(stmt.if_blocks or {}) do
        table.insert(result, if_block.body)
    end
    return result
end

local function stmt_child_surface_ranges(
    ctx: RenderContext, stmt: ast.Node
): {source.Range}
    local result: {source.Range} = {}
    for _, child_block in ipairs(stmt_child_blocks(stmt)) do
        local range = block_surface_range(ctx, child_block)
        if range ~= nil then
            table.insert(result, range)
        end
    end
    return result
end

local function stmt_overlaps_fmt_off(ctx: RenderContext, stmt: ast.Node): boolean
    -- The geometry below is the expensive part of a block render; a file with no
    -- fmt:off regions never needs it.
    if ctx.fmt_off_regions:is_empty() then
        return false
    end
    local last_line = max_source_line(ctx, stmt)
    local own_ranges = source.subtract_many(
        {source.Range.new(stmt.y, last_line)}, stmt_child_surface_ranges(ctx, stmt)
    )
    for _, range in ipairs(own_ranges) do
        if ctx.fmt_off_regions:includes_range(range.first_line, range.last_line) then
            return true
        end
    end

    -- The own-range check above subtracts child blocks so an enclosing
    -- statement can stay structural while only its body is frozen. Structural
    -- rendering puts the enclosing `end` on the statement's closing line, which
    -- collides when a frozen child's verbatim text reaches that same line: the
    -- `end` would be emitted both verbatim and structurally. Freeze the whole
    -- statement so its source is emitted once.
    for _, child_block in ipairs(stmt_child_blocks(stmt)) do
        for _, child in ipairs(child_block) do
            if
                max_source_line(ctx, child) == last_line
                and stmt_overlaps_fmt_off(ctx, child)
            then
                return true
            end
        end
    end
    return false
end

-- A run is a maximal sequence of consecutive frozen statements whose source
-- lines stay contiguous. Its lines are emitted verbatim as a single block, so
-- the seams between statements never need stitching.
local record Run
    first_line: integer
    last_line: integer
    first_stmt: ast.Node
    last_stmt: ast.Node
end

function Run.new(
    first_line: integer, last_line: integer, first_stmt: ast.Node, last_stmt: ast.Node
): Run
    local self: Run = setmetatable({}, {__index = Run})
    self.first_line = first_line
    self.last_line = last_line
    self.first_stmt = first_stmt
    self.last_stmt = last_stmt
    return self
end

-- A block partitions into segments: each is either a frozen Run or a single
-- structural statement. Grouping resolves all run boundaries up front so that
-- rendering is a flat walk with no index arithmetic.
local record Segment
    run: Run
    stmt: ast.Node
end

function Segment.frozen(run: Run): Segment
    local self: Segment = setmetatable({}, {__index = Segment})
    self.run = run
    return self
end

function Segment.structural(stmt: ast.Node): Segment
    local self: Segment = setmetatable({}, {__index = Segment})
    self.stmt = stmt
    return self
end

-- The first source line a frozen statement contributes: its own line, extended
-- back to cover any leading comment that falls inside a frozen region after the
-- previous emission boundary.
local function back_extended_first_line(
    ctx: RenderContext, stmt: ast.Node, previous_boundary: integer
): integer
    local first_line = stmt.y
    for _, comment in ipairs(ctx.slots:leading_comments(stmt)) do
        if
            comment.y > previous_boundary
            and ctx.fmt_off_regions:includes_line(comment.y)
        then
            first_line = math.min(first_line, comment.y)
        end
    end
    return first_line
end

-- Guards run continuation: an unfrozen line between two frozen statements
-- (e.g. a `-- fmt:on` directive) must break the run so that gap renders
-- structurally. Tests the open interval `(after, before)`.
local function gap_fully_frozen(
    fmt_off_regions: source.Regions, after: integer, before: integer
): boolean
    for line = after + 1, before - 1 do
        if not fmt_off_regions:includes_line(line) then
            return false
        end
    end
    return true
end

-- Group the maximal contiguous run of frozen statements starting at `start_idx`
-- and resolve its source line span. Returns the run and the index of its last
-- statement so the caller can resume after it.
local function build_run(
    ctx: RenderContext,
    block: ast.Node,
    start_idx: integer,
    previous_boundary: integer,
    block_dangling: {ast.Comment}
): Run, integer
    local first_stmt = block[start_idx]
    local first_line = back_extended_first_line(ctx, first_stmt, previous_boundary)
    local end_idx = start_idx
    local last_line = verbatim_extent(ctx, first_stmt, block_dangling)
    for candidate_idx = start_idx + 1, #block do
        local candidate = block[candidate_idx]
        if not stmt_overlaps_fmt_off(ctx, candidate) then
            break
        end
        local next_first = back_extended_first_line(ctx, candidate, last_line)
        if not gap_fully_frozen(ctx.fmt_off_regions, last_line, next_first) then
            break
        end
        end_idx = candidate_idx
        last_line = verbatim_extent(ctx, candidate, block_dangling)
    end
    return Run.new(first_line, last_line, first_stmt, block[end_idx]), end_idx
end

local function code_precedes_on_line(
    source_lines: {string}, line: integer, column: integer
): boolean
    return source_lines[line]:sub(1, column - 1):match("%S") ~= nil
end

-- nil when the next segment is a frozen run (its `.stmt` is nil) or there is none.
local function next_structural_stmt(segments: {Segment}, idx: integer): ast.Node
    local next_segment = segments[idx + 1]
    if next_segment == nil then
        return nil
    end
    return next_segment.stmt
end

-- Column on the run's last line where structural code resumes, or nil when the run
-- owns the rest of the line. A sibling statement always precedes the block's closer,
-- so at most one of the two can apply.
local function last_line_structural_col(
    block: ast.Node, run: Run, next_structural: ast.Node
): integer
    if next_structural ~= nil and next_structural.y == run.last_line then
        return next_structural.x
    end
    if block.yend == run.last_line then
        return block.close_x
    end
    return nil
end

local function collect_run_lines(
    source_lines: {string}, run: Run, start_col: integer, last_line_cut_col?: integer
): {string}
    local result: {string} = {}
    -- A single-line run can carry a structural prefix and/or a following
    -- structural token on the same line; slice the frozen middle out of it.
    if run.first_line == run.last_line then
        local line_str = source_lines[run.last_line]
        local stop = #line_str
        if last_line_cut_col ~= nil then
            stop = last_line_cut_col - 1
        end
        local frozen = line_str:sub(start_col, stop):gsub("%s+$", "")
        if frozen ~= "" then
            table.insert(result, frozen)
        end
        return result
    end

    table.insert(result, source_lines[run.first_line]:sub(start_col))
    for line = run.first_line + 1, run.last_line do
        table.insert(result, source_lines[line])
    end

    -- The run's last line may continue with structurally-rendered code: a
    -- following sibling statement or the block's closing keyword (e.g.
    -- `end --[[c]] local type`, `..0 until ...`). Stop the verbatim text before it
    -- so the structural pass emits it once, without duplication.
    if last_line_cut_col ~= nil then
        local truncated = (
            source_lines[run.last_line]:sub(1, last_line_cut_col - 1):gsub("%s+$", "")
        )
        if truncated == "" then
            table.remove(result)
        else
            result[#result] = truncated
        end
    end

    return result
end

local function blank_before_fmt_off_start(ctx: RenderContext, stmt: ast.Node): boolean
    for _, comment in ipairs(ctx.slots:leading_comments(stmt)) do
        if ctx.fmt_off_regions:includes_line(comment.y) then
            return comment.blank_line_before
        end
    end
    return stmt.blank_line_before
end

-- Partition a block into its frozen runs and structural statements. All
-- run-boundary arithmetic lives here, so the renderer walks a flat list.
local function group_segments(
    ctx: RenderContext, block: ast.Node, block_dangling: {ast.Comment}
): {Segment}
    local segments: {Segment} = {}
    local previous_boundary = 0
    local consumed = 0
    for idx, stmt in ipairs(block) do
        if idx > consumed then
            if stmt_overlaps_fmt_off(ctx, stmt) then
                local run, run_end_idx = build_run(
                    ctx, block, idx, previous_boundary, block_dangling
                )
                consumed = run_end_idx
                previous_boundary = run.last_line
                table.insert(segments, Segment.frozen(run))
            else
                previous_boundary = stmt.yend
                table.insert(segments, Segment.structural(stmt))
            end
        end
    end
    return segments
end

local function render_block_doc(ctx: RenderContext, block: ast.Node): doc.Doc | nil
    local parts: {doc.Doc} = {}
    local verbatim_boundary: integer = 0
    local line_before = false

    local block_dangling = ctx.slots:dangling_comments(block)
    local segments = group_segments(ctx, block, block_dangling)
    for idx, segment in ipairs(segments) do
        if segment.run ~= nil then
            local run = segment.run
            local pre_fmt_off: {ast.Comment} = {}
            for _, comment in ipairs(ctx.slots:leading_comments(run.first_stmt)) do
                if not ctx.fmt_off_regions:includes_line(comment.y) then
                    table.insert(pre_fmt_off, comment)
                end
            end
            -- Structural code may precede the freeze column on the run's first
            -- line (e.g. `local function f() -- fmt:off`); keep only the frozen
            -- suffix so the already-rendered prefix is not duplicated.
            local start_col = 1
            if
                run.first_line == run.first_stmt.y
                and code_precedes_on_line(
                    ctx.source_lines, run.first_line, run.first_stmt.x
                )
            then
                start_col = run.first_stmt.x
            end
            local last_line_cut_col = last_line_structural_col(
                block, run, next_structural_stmt(segments, idx)
            )
            local verbatim_lines = collect_run_lines(
                ctx.source_lines, run, start_col, last_line_cut_col
            )
            -- The raw lines carry their comments already; mark them consumed so
            -- the enclosing statement's sweep does not relocate a copy.
            ctx.tokens:consume_slice(
                run.first_line, start_col, run.last_line, last_line_cut_col
            )
            if #pre_fmt_off > 0 or #verbatim_lines > 0 then
                line_before = render_builders.append_comment_docs(
                    parts, pre_fmt_off, line_before
                )
                if line_before then
                    table.insert(parts, doc.hardline())
                end
                if blank_before_fmt_off_start(
                    ctx, run.first_stmt
                ) then
                    table.insert(parts, doc.hardline())
                end
                if #verbatim_lines > 0 then
                    table.insert(parts, doc.raw(verbatim_lines))
                end
            end
            verbatim_boundary = run.last_line
        else
            local stmt = segment.stmt
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
                return nil
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

            line_before = render_builders.append_comment_docs(
                parts, leading, line_before
            )
            line_before = render_builders.append_comment_docs(parts, swept, line_before)
            table.insert(
                parts,
                render_builders.append_lines_pre_node(
                    stmt, line_before, doc.stmt_sep_line()
                )
            )
            table.insert(parts, node_doc)
            table.insert(parts, render_builders.trailing_comment_doc(trailing))
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
