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
    -- Last source line the node's own text reaches, or 0 if none.
    -- The parser sets `yend` only when it closes a node on a real token. An unclosed
    -- node has no `yend`, and its `y` is the next token's line, which can fall far
    -- past the node, even to EOF after error recovery. A value-less `return` is one
    -- case: its empty expression list is anchored on the token after `return`. So a
    -- bare `y` is a start position, not an extent; only `yend` and trailing comments
    -- count toward the reach.
    local last = node.yend or 0
    for _, c in ipairs(node.trailing_comments or {}) do
        if c.yend > last then
            last = c.yend
        end
    end
    return last
end

local function max_source_line(node: parser.Node): integer
    local max_line = node_end_line(node)

    local function set_max_line(child: parser.Node)
        local child_end = node_end_line(child)
        if child_end > max_line then
            max_line = child_end
        end
    end

    ast_traversal.walk_descendants(node, set_max_line)
    return max_line
end

local function verbatim_extent(
    stmt: parser.Node, block_dangling: {parser.Comment}
): integer
    -- verbatime needs to include any dangling comments
    -- for enclosing block that overlap with statement
    local last = max_source_line(stmt)
    for _, comment in ipairs(block_dangling) do
        if comment.y <= last then
            last = math.max(last, comment.yend)
        end
    end
    return last
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

-- A run is a maximal sequence of consecutive frozen statements whose source
-- lines stay contiguous. Its lines are emitted verbatim as a single block, so
-- the seams between statements never need stitching.
local record Run
    first_line: integer
    last_line: integer
    first_stmt: parser.Node
    last_stmt: parser.Node
end

function Run.new(
    first_line: integer,
    last_line: integer,
    first_stmt: parser.Node,
    last_stmt: parser.Node
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
    stmt: parser.Node
end

function Segment.frozen(run: Run): Segment
    local self: Segment = setmetatable({}, {__index = Segment})
    self.run = run
    return self
end

function Segment.structural(stmt: parser.Node): Segment
    local self: Segment = setmetatable({}, {__index = Segment})
    self.stmt = stmt
    return self
end

-- The first source line a frozen statement contributes: its own line, extended
-- back to cover any leading comment that falls inside a frozen region after the
-- previous emission boundary.
local function back_extended_first_line(
    stmt: parser.Node, previous_boundary: integer, fmt_off_regions: source.Regions
): integer
    local first_line = stmt.y
    for _, comment in ipairs(stmt.leading_comments or {}) do
        if
            comment.y > previous_boundary and fmt_off_regions:includes_line(comment.y)
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
    block: parser.Node,
    start_idx: integer,
    previous_boundary: integer,
    fmt_off_regions: source.Regions,
    block_dangling: {parser.Comment}
): Run, integer
    local first_stmt = block[start_idx]
    local first_line = back_extended_first_line(
        first_stmt, previous_boundary, fmt_off_regions
    )
    local end_idx = start_idx
    local last_line = verbatim_extent(first_stmt, block_dangling)
    for candidate_idx = start_idx + 1, #block do
        local candidate = block[candidate_idx]
        if not stmt_overlaps_fmt_off(candidate, fmt_off_regions) then
            break
        end
        local next_first = back_extended_first_line(
            candidate, last_line, fmt_off_regions
        )
        if not gap_fully_frozen(fmt_off_regions, last_line, next_first) then
            break
        end
        end_idx = candidate_idx
        last_line = verbatim_extent(candidate, block_dangling)
    end
    return Run.new(first_line, last_line, first_stmt, block[end_idx]), end_idx
end

local function code_precedes_on_line(
    source_lines: {string}, line: integer, column: integer
): boolean
    return source_lines[line]:sub(1, column - 1):match("%S") ~= nil
end

-- nil when the next segment is a frozen run (its `.stmt` is nil) or there is none.
local function next_structural_stmt(segments: {Segment}, idx: integer): parser.Node
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
    block: parser.Node, run: Run, next_structural: parser.Node
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
    source_lines: {string},
    run: Run,
    code_precedes_run: boolean,
    last_line_cut_col?: integer
): {string}
    local result: {string} = {}
    -- Structural code may precede the freeze column on the run's first line
    -- (e.g. `local function f() -- fmt:off`); keep only the frozen suffix so the
    -- already-rendered prefix is not duplicated.
    local start_col = 1
    if code_precedes_run then
        start_col = run.first_stmt.x
    end

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

-- Partition a block into its frozen runs and structural statements. All
-- run-boundary arithmetic lives here, so the renderer walks a flat list.
local function group_segments(
    block: parser.Node,
    fmt_off_regions: source.Regions,
    block_dangling: {parser.Comment}
): {Segment}
    local segments: {Segment} = {}
    local previous_boundary = 0
    local consumed = 0
    for idx, stmt in ipairs(block) do
        if idx > consumed then
            if stmt_overlaps_fmt_off(stmt, fmt_off_regions) then
                local run, run_end_idx = build_run(
                    block, idx, previous_boundary, fmt_off_regions, block_dangling
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

local function render_block_doc(ctx: RenderContext, block: parser.Node): doc.Doc | nil
    local parts: {doc.Doc} = {}
    local verbatim_boundary: integer = 0
    local line_before = false

    local segments = group_segments(
        block, ctx.fmt_off_regions, block.dangling_comments or {}
    )
    for idx, segment in ipairs(segments) do
        if segment.run ~= nil then
            local run = segment.run
            local pre_fmt_off: {parser.Comment} = {}
            for _, comment in ipairs(run.first_stmt.leading_comments or {}) do
                if not ctx.fmt_off_regions:includes_line(comment.y) then
                    table.insert(pre_fmt_off, comment)
                end
            end
            local code_precedes_run = run.first_line == run.first_stmt.y
                and code_precedes_on_line(
                    ctx.source_lines, run.first_line, run.first_stmt.x
                )
            local verbatim_lines = collect_run_lines(
                ctx.source_lines,
                run,
                code_precedes_run,
                last_line_structural_col(
                    block, run, next_structural_stmt(segments, idx)
                )
            )
            if #pre_fmt_off > 0 or #verbatim_lines > 0 then
                line_before = render_builders.append_comment_docs(
                    parts, pre_fmt_off, line_before
                )
                if line_before then
                    table.insert(parts, doc.hardline())
                end
                if blank_before_fmt_off_start(run.first_stmt, ctx.fmt_off_regions) then
                    table.insert(parts, doc.hardline())
                end
                if #verbatim_lines > 0 then
                    table.insert(parts, doc.raw(verbatim_lines))
                end
            end
            verbatim_boundary = run.last_line
        else
            local stmt = segment.stmt
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
