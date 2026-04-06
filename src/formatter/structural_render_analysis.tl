-- Decides whether a block can be structurally re-rendered by block_doc.
-- Rejects blocks with comments, fmt:off, unsupported statement shapes,
-- multi-statement anonymous functions in expressions, or multi-line conditions.
local ast_utils = require("formatter.ast_utils")
local fmt_logger = require("formatter.fmt_logger")
local layout_types = require("formatter.layout_types")
local parser = require("formatter.parser")
local ranges = require("formatter.ranges")
local tl = require("tl")

local type StatementLayout = layout_types.StatementLayout
local type BlockLayout = layout_types.BlockLayout

local record AnalysisResult
    can_render_structurally: boolean
    block_layout: BlockLayout
end

local structural_render_analysis = {
    BlockLayout = layout_types.BlockLayout,
    StatementLayout = layout_types.StatementLayout,
    AnalysisResult = AnalysisResult,
}

function AnalysisResult.new(
    can_render_structurally: boolean, block_layout: BlockLayout
): AnalysisResult
    local self: AnalysisResult = setmetatable({}, {__index = AnalysisResult})
    self.can_render_structurally = can_render_structurally
    self.block_layout = block_layout
    return self
end

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function max_source_line(node: parser.Node): integer
    local max_line = node.yend or node.y

    ast_utils.walk_descendants(node, function(child: parser.Node)
        local child_end = node_end_line(child)
        if child_end > max_line then
            max_line = child_end
        end
    end)

    return max_line
end

local function min_source_line(node: parser.Node): integer
    local min_line = node.y

    local function consider_comments(comments: {parser.Comment})
        for _, comment in ipairs(comments) do
            if comment.y < min_line then
                min_line = comment.y
            end
        end
    end

    local function consider_node_comments(candidate: parser.Node)
        consider_comments(candidate.comments or {})
        consider_comments(candidate.end_comments or {})
        consider_comments(candidate.unattached_comments or {})
    end

    consider_node_comments(node)
    ast_utils.walk_descendants(node, consider_node_comments)
    return min_line
end

local function node_is_single_line(node: parser.Node): boolean
    return max_source_line(node) == node.y
end

local function count_leading_comments_for_stmt(
    stmt: parser.Node, previous_end_line: integer
): integer
    local count = 0
    if stmt.comments ~= nil then
        for _, comment in ipairs(stmt.comments) do
            if comment.y > previous_end_line then
                count = count + 1
            end
        end
    end
    return count
end

local function anonymous_function_stmt_is_renderable(stmt: parser.Node): boolean
    return stmt.kind == "return"
        or stmt.kind == "assignment"
        or stmt.kind == "local_declaration"
end

local function anonymous_function_is_renderable(node: parser.Node): boolean
    if node.kind ~= "function" then
        return true
    end
    if node.body == nil or #node.body == 0 then
        return true
    end
    if #node.body > 1 then
        return false
    end
    return anonymous_function_stmt_is_renderable(node.body[1])
end

local function node_contains_unrenderable_anonymous_function(
    node: parser.Node
): boolean
    if not anonymous_function_is_renderable(node) then
        return true
    end

    local found = false
    ast_utils.walk_descendants(node, function(child: parser.Node)
        if not found and child.kind == "function" and not anonymous_function_is_renderable(child) then
            found = true
        end
    end)
    return found
end

local function exps_contain_unrenderable_anonymous_function(
    exps: {parser.Node}
): boolean
    for _, exp in ipairs(exps) do
        if node_contains_unrenderable_anonymous_function(exp) then
            return true
        end
    end
    return false
end

local function exps_contain_multiline_table(exps: {parser.Node}): boolean
    for _, exp in ipairs(exps) do
        if exp.kind == "literal_table"
            and not exp.trailing_comma
            and ast_utils.has_multiline_descendant(exp)
        then
            return true
        end
    end
    return false
end

local function top_level_block_has_leading_prelude(
    block: parser.Node, lines: {string}
): boolean
    if block.x ~= 1 or #block == 0 then
        return false
    end

    local first_stmt = block[1]
    for line = 1, first_stmt.y - 1 do
        local line_str = lines[line]
        if line_str ~= nil
            and line_str:match("%S") ~= nil
            and line_str:match("^%s*%-%-") == nil
        then
            return true
        end
    end

    return false
end

local function local_type_is_ast_renderable(stmt: parser.Node): boolean
    if stmt.value == nil then
        return false
    end
    if stmt.value.kind ~= "newtype" then
        return node_is_single_line(stmt)
    end
    if stmt.value.newtype == nil then
        return false
    end
    local def = stmt.value.newtype.def
    if def == nil then
        return false
    end
    if def is tl.GenericType then
        def = def.t
        if def == nil then
            return false
        end
    end
    if def.typename ~= "record" and def.typename ~= "interface" then
        return true
    end

    local record_like = def as tl.RecordLikeType
    if record_like.meta_field_order ~= nil and #record_like.meta_field_order > 0 then
        if def.typename ~= "interface" then
            return false
        end
        if #record_like.meta_field_order ~= 1 or record_like.meta_field_order[1] ~= "__is" then
            return false
        end
        local where_function = record_like.meta_fields["__is"]
        if where_function == nil then
            return false
        end
    end

    return true
end

local function stmt_is_ast_renderable(stmt: parser.Node): boolean
    if stmt.kind == "return" then
        return stmt.exps == nil
            or not exps_contain_unrenderable_anonymous_function(stmt.exps)
    elseif stmt.kind == "assignment" then
        return not exps_contain_unrenderable_anonymous_function(stmt.exps)
    elseif stmt.kind == "local_declaration" then
        return (stmt.exps == nil or not exps_contain_unrenderable_anonymous_function(stmt.exps))
            and (stmt.exps == nil or not exps_contain_multiline_table(stmt.exps))
    elseif stmt.kind == "local_type" then
        return local_type_is_ast_renderable(stmt)
    elseif stmt.kind == "op" then
        if stmt.op ~= nil and stmt.op.op == "@funcall" then
            return not node_contains_unrenderable_anonymous_function(stmt)
        end
        return node_is_single_line(
            stmt
        ) and not node_contains_unrenderable_anonymous_function(stmt)
    elseif stmt.kind == "break" then
        return true
    elseif stmt.kind == "local_function"
        or stmt.kind == "global_function"
        or stmt.kind == "record_function"
    then
        return stmt.args ~= nil
    elseif stmt.kind == "if" and stmt.if_blocks ~= nil then
        return true
    elseif stmt.kind == "while" and stmt.exp ~= nil then
        return node_is_single_line(stmt.exp)
    elseif stmt.kind == "fornum"
        and stmt.from ~= nil
        and stmt.to ~= nil
    then
        if not node_is_single_line(stmt.from) then
            return false
        end
        if not node_is_single_line(stmt.to) then
            return false
        end
        if stmt.step ~= nil and not node_is_single_line(stmt.step) then
            return false
        end
        return true
    elseif stmt.kind == "forin" then
        return true
    elseif stmt.kind == "repeat" and stmt.exp ~= nil then
        return node_is_single_line(stmt.exp)
    elseif stmt.kind == "do" then
        return true
    end

    return false
end

local function stmt_surface_range(stmt: parser.Node): ranges.LineRange
    return ranges.new(stmt.y, max_source_line(stmt))
end

local function block_surface_range(block: parser.Node): ranges.LineRange
    return ranges.new(min_source_line(block), max_source_line(block))
end

local function stmt_child_surface_ranges(stmt: parser.Node): {ranges.LineRange}
    local result: {ranges.LineRange} = {}

    if stmt.body ~= nil then
        table.insert(result, block_surface_range(stmt.body))
    end

    for _, if_block in ipairs(stmt.if_blocks or {}) do
        table.insert(result, block_surface_range(if_block))
    end

    return result
end

local function stmt_own_surface_ranges(stmt: parser.Node): {ranges.LineRange}
    return ranges.subtract_many(
        { stmt_surface_range(stmt) },
        stmt_child_surface_ranges(stmt)
    )
end

local function stmt_overlaps_fmt_off(
    stmt: parser.Node, fmt_off_regions: ast_utils.FmtOffRegions
): boolean
    local surface_ranges = stmt_own_surface_ranges(stmt)
    for _, range in ipairs(surface_ranges) do
        if fmt_off_regions:includes_range(range.first_line, range.last_line) then
            return true
        end
    end
    return false
end

local function collect_verbatim_lines(
    source_lines: {string},
    stmt: parser.Node,
    stmt_end_line: integer,
    previous_end_line: integer
): {string}
    local first_line = stmt.y

    for _, comment in ipairs(stmt.comments or {}) do
        if comment.y > previous_end_line then
            first_line = math.min(first_line, comment.y)
        end
    end

    local result: {string} = {}
    for line = first_line, stmt_end_line do
        local source_line = source_lines[line] or ""
        table.insert(result, source_line)
    end

    return result
end

local function build_block_layout(
    block: parser.Node,
    fmt_off_regions: ast_utils.FmtOffRegions,
    source_lines: {string}
): BlockLayout | nil
    if #block == 0 then
        return layout_types.BlockLayout.new({})
    end

    local previous_end: integer | nil = nil
    local statement_layouts: {StatementLayout} = {}
    for _, stmt in ipairs(block) do
        local stmt_end = max_source_line(stmt)
        if not (previous_end is nil) and stmt.y > previous_end + 1 then
            local non_nil_previous_end = previous_end
            local leading_comment_count = count_leading_comments_for_stmt(
                stmt, non_nil_previous_end
            )
            local effective_blank_lines =
                stmt.y - non_nil_previous_end - 1 - leading_comment_count
            if effective_blank_lines > 0 then
                statement_layouts[#statement_layouts].preserve_blank_line_after = true
            end
        end
        local statement_layout = layout_types.StatementLayout.new()
        local stmt_is_verbatim = stmt_overlaps_fmt_off(stmt, fmt_off_regions)

        if stmt_is_verbatim then
            statement_layout.render_mode = "verbatim"
            statement_layout.verbatim_lines = collect_verbatim_lines(
                source_lines, stmt, stmt_end, previous_end or 0
            )
        else
            if not stmt_is_ast_renderable(stmt) then
                fmt_logger.info(
                    "[structural] blocked at line %s: %s has unsafe source shape",
                    tostring(stmt.y),
                    stmt.kind
                )
                return nil
            end
        end

        if stmt.body ~= nil then
            local body_layout = build_block_layout(
                stmt.body, fmt_off_regions, source_lines
            )
            if body_layout == nil then
                return nil
            end
            statement_layout.body_layout = body_layout
        end
        for _, if_block in ipairs(stmt.if_blocks or {}) do
            if if_block.body == nil then
                fmt_logger.info(
                    "[structural] blocked at line %s: if block at line %s has no body",
                    tostring(stmt.y),
                    tostring(if_block.y)
                )
                return nil
            end
            local if_block_layout = build_block_layout(
                if_block.body, fmt_off_regions, source_lines
            )
            if if_block_layout is nil then
                return nil
            end
            table.insert(statement_layout.if_block_layouts, if_block_layout)
        end

        table.insert(statement_layouts, statement_layout)
        previous_end = stmt_end
    end

    return layout_types.BlockLayout.new(statement_layouts)
end

local function block_is_structurally_eligible(
    block: parser.Node, lines: {string}, fmt_off_regions: ast_utils.FmtOffRegions
): boolean
    if #block == 0 then
        return true
    end
    if top_level_block_has_leading_prelude(block, lines) then
        fmt_logger.info("[structural] blocked: top-level block has leading prelude")
        return false
    end

    for _, stmt in ipairs(block) do
        local stmt_end = max_source_line(stmt)
        if fmt_off_regions:includes_range(stmt.y, stmt_end) then
            fmt_logger.info(
                "[structural] blocked at line %s: fmt:off covers %s",
                tostring(stmt.y),
                stmt.kind
            )
            return false
        end
        if stmt.body ~= nil and not block_is_structurally_eligible(
            stmt.body, lines, fmt_off_regions
        ) then
            fmt_logger.info(
                "[structural] blocked at line %s: %s body blocked structural rendering",
                tostring(stmt.y),
                stmt.kind
            )
            return false
        end
        if stmt.if_blocks ~= nil then
            for _, if_block in ipairs(stmt.if_blocks) do
                if not block_is_structurally_eligible(
                    if_block.body, lines, fmt_off_regions
                ) then
                    fmt_logger.info(
                        "[structural] blocked at line %s: if block body at line %s blocked structural rendering",
                        tostring(stmt.y),
                        tostring(if_block.y)
                    )
                    return false
                end
            end
        end
    end

    return true
end

function structural_render_analysis.analyze_block(
    block: parser.Node,
    source_lines: {string},
    fmt_off_regions: ast_utils.FmtOffRegions
): AnalysisResult
    local block_layout = build_block_layout(block, fmt_off_regions, source_lines)
    if block_layout == nil then
        return AnalysisResult.new(false, nil)
    end

    local can_render_structurally = block_is_structurally_eligible(
        block, source_lines, ast_utils.FmtOffRegions.new({})
    )
    if not can_render_structurally then
        return AnalysisResult.new(false, nil)
    end

    return AnalysisResult.new(true, block_layout)
end

return structural_render_analysis
