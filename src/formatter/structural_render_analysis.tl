-- Decides whether a block can be structurally re-rendered by block_doc.
-- Rejects blocks with comments, fmt:off, unsupported statement shapes,
-- multi-statement anonymous functions in expressions, or multi-line conditions.
local ast_utils = require("formatter.ast_utils")
local fmt_logger = require("formatter.fmt_logger")
local parser = require("formatter.parser")
local tl = require("tl")

local record StatementLayout
    preserve_blank_line_after: boolean
    body_layout: BlockLayout
    if_block_layouts: {BlockLayout} | nil
end

local record BlockLayout
    statements: {StatementLayout}
end

local structural_render_analysis = {
    BlockLayout = BlockLayout, StatementLayout = StatementLayout
}

function StatementLayout.new(): StatementLayout
    local self: StatementLayout = setmetatable({}, { __index = StatementLayout })
    self.preserve_blank_line_after = false
    self.body_layout = nil
    self.if_block_layouts = nil
    return self
end

function BlockLayout.new(statements: {StatementLayout}): BlockLayout
    local self: BlockLayout = setmetatable({}, { __index = BlockLayout })
    self.statements = statements
    return self
end

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function node_child_end_line(node: parser.Node): integer
    if node.kind == "expression_list" then
        return node.y
    end

    return node_end_line(node)
end

local function max_source_line(node: parser.Node): integer
    local max_line = node.y

    ast_utils.walk_descendants(node, function(child: parser.Node)
        local child_end = node_child_end_line(child)
        if child_end > max_line then
            max_line = child_end
        end
    end)

    return max_line
end

local function max_statement_source_line(node: parser.Node): integer
    local max_line = node.y

    local function consider(child: parser.Node)
        local child_end = node_child_end_line(child)
        if child_end > max_line then
            max_line = child_end
        end

        if child.kind == "op" and child.op ~= nil and child.op.op == "@funcall" and child.e2 ~= nil then
            local args_end = max_source_line(child.e2)
            if args_end > child.e2.y and args_end + 1 > max_line then
                max_line = args_end + 1
            end
        end
    end

    consider(node)
    ast_utils.walk_descendants(node, consider)
    return max_line
end

local function node_is_single_line(node: parser.Node): boolean
    return max_source_line(node) == node.y
end

local function node_list_is_single_line(nodes: parser.Node): boolean
    for _, child in ipairs(nodes) do
        if not node_is_single_line(child) then
            return false
        end
    end

    return true
end

local function has_comment(
    lines: {string}, start_line: integer, end_line: integer
): boolean
    for line = start_line, end_line do
        if lines[line] ~= nil and lines[line]:find("%-%-") ~= nil then
            return true
        end
    end
    return false
end

local function has_non_empty_line_between(
    lines: {string}, start_line: integer, end_line: integer
): boolean
    for line = start_line, end_line do
        if lines[line] ~= nil and lines[line]:match("%S") ~= nil then
            return true
        end
    end

    return false
end

local function count_empty_lines_between(
    lines: {string}, start_line: integer, end_line: integer
): integer
    local count = 0

    for line = start_line, end_line do
        if lines[line] ~= nil and lines[line]:match("%S") == nil then
            count = count + 1
        end
    end

    return count
end

local function node_contains_multi_statement_function(node: parser.Node): boolean
    if node.kind == "function" and node.body ~= nil and #node.body > 1 then
        return true
    end
    local found = false
    ast_utils.walk_descendants(node, function(child: parser.Node)
        if child.kind == "function" and child.body ~= nil and #child.body > 1 then
            found = true
        end
    end)
    return found
end

local function exps_contain_multi_statement_function(exps: {parser.Node}): boolean
    for _, exp in ipairs(exps) do
        if node_contains_multi_statement_function(exp) then
            return true
        end
    end
    return false
end

local function exps_contain_multiline_table(exps: {parser.Node}): boolean
    for _, exp in ipairs(exps) do
        if exp.kind == "literal_table" and ast_utils.has_multiline_descendant(exp) then
            return true
        end
    end
    return false
end

local function exps_contain_multiline_function(exps: {parser.Node}): boolean
    for _, exp in ipairs(exps) do
        if exp.kind == "function" and exp.yend ~= nil and exp.yend > exp.y then
            return true
        end
    end
    return false
end

local function table_has_magic_trailing_comma(
    node: parser.Node, lines: {string}
): boolean
    if node.yend == nil or node.yend <= node.y then
        return false
    end
    local last_body_line = lines[node.yend - 1]
    return last_body_line ~= nil and last_body_line:match(",%s*$") ~= nil
end

local function stmt_exps_contain_magic_trailing_comma_table(
    stmt: parser.Node, lines: {string}
): boolean
    local exps = stmt.exps
    if exps == nil then
        return false
    end
    for _, exp in ipairs(exps) do
        if exp.kind == "literal_table" and table_has_magic_trailing_comma(
           exp, lines
        ) then
            return true
        end
    end
    return false
end

local function block_has_unattached_comments(block: parser.Node): boolean
    return block.unattached_comments ~= nil and #block.unattached_comments > 0
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
        if line_str ~= nil and line_str:match("%S") ~= nil then
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

local function return_has_fragile_multiline_call_trailing_content(
    stmt: parser.Node, lines: {string}
): boolean
    if stmt.kind ~= "return" or stmt.exps == nil then
        return false
    end

    local found = false
    for _, exp in ipairs(stmt.exps) do
        ast_utils.walk_descendants(exp, function(child: parser.Node)
            if found then
                return
            end

            if child.kind == "op" and child.op ~= nil and child.op.op == "@funcall" and child.e2 ~= nil then
                local args = child.e2
                if args.yend ~= nil and args.yend > args.y then
                    local close_line = lines[args.yend]
                    if close_line ~= nil and close_line:sub(args.xend + 1):match("%S") ~= nil then
                        found = true
                    end
                end
            end
        end)
        if found then
            return true
        end
    end

    return false
end

local function stmt_is_ast_renderable(stmt: parser.Node): boolean
    if stmt.kind == "return" then
        return stmt.exps == nil or not exps_contain_multi_statement_function(stmt.exps)
    elseif stmt.kind == "assignment" then
        return not exps_contain_multi_statement_function(stmt.exps)
    elseif stmt.kind == "local_declaration" then
        return (stmt.exps == nil or not exps_contain_multi_statement_function(stmt.exps))
            and (stmt.exps == nil or not exps_contain_multiline_table(stmt.exps))
            and (stmt.exps == nil or not exps_contain_multiline_function(stmt.exps))
    elseif stmt.kind == "local_type" then
        return local_type_is_ast_renderable(stmt)
    elseif stmt.kind == "op" then
        return node_is_single_line(stmt) and not node_contains_multi_statement_function(stmt)
    elseif stmt.kind == "break" then
        return true
    elseif stmt.kind == "local_function"
        or stmt.kind == "global_function"
        or stmt.kind == "record_function"
    then
        return stmt.args ~= nil and node_list_is_single_line(stmt.args)
    elseif stmt.kind == "if" and stmt.if_blocks ~= nil then
        for _, if_block in ipairs(stmt.if_blocks) do
            if if_block.exp ~= nil and not node_is_single_line(if_block.exp) then
                return false
            end
        end
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
    elseif stmt.kind == "forin" and stmt.vars ~= nil and stmt.exps ~= nil then
        return node_list_is_single_line(stmt.vars) and node_list_is_single_line(stmt.exps)
    elseif stmt.kind == "repeat" and stmt.exp ~= nil then
        return node_is_single_line(stmt.exp)
    elseif stmt.kind == "do" then
        return true
    end

    return false
end

local function build_block_layout(block: parser.Node): BlockLayout | nil
    if #block == 0 then
        return nil
    end

    local previous_end: integer | nil = nil
    local statement_layouts: {StatementLayout} = {}
    for _, stmt in ipairs(block) do
        local stmt_end = max_statement_source_line(stmt)
        if not (previous_end is nil) and stmt.y > previous_end + 1 then
            statement_layouts[#statement_layouts].preserve_blank_line_after = true
        end
        if not stmt_is_ast_renderable(stmt) then
            fmt_logger.info(
                "[structural] blocked at line %s: %s has unsafe source shape",
                tostring(stmt.y),
                stmt.kind
            )
            return nil
        end
        local statement_layout = StatementLayout.new()
        if stmt.body ~= nil then
            local body_layout = build_block_layout(stmt.body)
            if body_layout == nil then
                return nil
            end
            statement_layout.body_layout = body_layout
        end
        if stmt.if_blocks ~= nil then
            local if_block_layouts: {BlockLayout} = {}
            for _, if_block in ipairs(stmt.if_blocks) do
                if if_block.body == nil then
                    fmt_logger.info(
                        "[structural] blocked at line %s: if block at line %s has no body",
                        tostring(stmt.y),
                        tostring(if_block.y)
                    )
                    return nil
                end
                local if_block_layout = build_block_layout(if_block.body)
                if if_block_layout is nil then
                    return nil
                end
                table.insert(if_block_layouts, if_block_layout)
            end
            statement_layout.if_block_layouts = if_block_layouts
        end
        table.insert(statement_layouts, statement_layout)
        previous_end = stmt_end
    end

    return BlockLayout.new(statement_layouts)
end

local function block_is_structurally_eligible(
    block: parser.Node, lines: {string}, fmt_off_regions: ast_utils.FmtOffRegions
): boolean
    if #block == 0 then
        return false
    end
    if block_has_unattached_comments(block) then
        fmt_logger.info("[structural] blocked: block has unattached comments")
        return false
    end
    if top_level_block_has_leading_prelude(block, lines) then
        fmt_logger.info("[structural] blocked: top-level block has leading prelude")
        return false
    end

    local previous_end: integer | nil = nil
    for _, stmt in ipairs(block) do
        local stmt_end = max_statement_source_line(stmt)
        if fmt_off_regions:includes_range(stmt.y, stmt_end) then
            fmt_logger.info(
                "[structural] blocked at line %s: fmt:off covers %s",
                tostring(stmt.y),
                stmt.kind
            )
            return false
        end
        if has_comment(lines, stmt.y, stmt_end) then
            fmt_logger.info(
                "[structural] blocked at line %s: comment in %s",
                tostring(stmt.y),
                stmt.kind
            )
            return false
        end
        if not (previous_end is nil) and stmt.y > previous_end + 1 then
            if has_non_empty_line_between(lines, previous_end + 1, stmt.y - 1) then
                fmt_logger.info(
                    "[structural] blocked at line %s: unexpected gap before %s",
                    tostring(stmt.y),
                    stmt.kind
                )
                return false
            end
            local empty_line_count = count_empty_lines_between(
                lines, previous_end + 1, stmt.y - 1
            )
            if empty_line_count < 1 then
                fmt_logger.info(
                    "[structural] blocked at line %s: unexpected gap before %s",
                    tostring(stmt.y),
                    stmt.kind
                )
                return false
            end
        end
        if stmt_exps_contain_magic_trailing_comma_table(stmt, lines) then
            fmt_logger.info(
                "[structural] blocked at line %s: %s has magic trailing comma table",
                tostring(stmt.y),
                stmt.kind
            )
            return false
        end
        if #block == 1 and return_has_fragile_multiline_call_trailing_content(
           stmt, lines
        ) then
            fmt_logger.info(
                "[structural] blocked at line %s: single return has multiline call trailing content",
                tostring(stmt.y)
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
        previous_end = stmt_end
    end

    return true
end

function structural_render_analysis.analyze_block_layout(block: parser.Node): BlockLayout | nil
    return build_block_layout(block)
end

function structural_render_analysis.can_use_block_doc_formatter(
    block: parser.Node, lines: {string}, fmt_off_regions: ast_utils.FmtOffRegions
): boolean
    if structural_render_analysis.analyze_block_layout(block) == nil then
        return false
    end
    return block_is_structurally_eligible(block, lines, fmt_off_regions)
end

return structural_render_analysis
