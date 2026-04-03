-- Decides whether a block can be structurally re-rendered by block_doc.
-- Rejects blocks with comments, fmt:off, unsupported statement shapes,
-- multi-statement anonymous functions in expressions, or multi-line conditions.
local ast_utils = require("formatter.ast_utils")
local parser = require("formatter.parser")

local record StatementLayout
    preserve_blank_line_after: boolean
    body_layout: any
    if_block_layouts: {any} | nil
end

local record BlockLayout
    statements: {StatementLayout}
end

local structural_render_analysis = {}

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

local function stmt_is_safe_source_shape(stmt: parser.Node): boolean
    if stmt.kind == "return" then
        return stmt.exps == nil or not exps_contain_multi_statement_function(stmt.exps)
    elseif stmt.kind == "assignment" then
        return not exps_contain_multi_statement_function(stmt.exps)
    elseif stmt.kind == "local_declaration" then
        return (stmt.exps == nil or not exps_contain_multi_statement_function(stmt.exps))
            and (stmt.exps == nil or not exps_contain_multiline_table(stmt.exps))
    elseif stmt.kind == "local_type" then
        return stmt.value ~= nil
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

function structural_render_analysis.analyze_block(
    block: parser.Node, lines: {string}, fmt_off_regions: ast_utils.FmtOffRegions
): BlockLayout | nil
    if #block == 0 then
        return nil
    end

    local previous_end: integer | nil = nil
    local statement_layouts: {StatementLayout} = {}
    for _, stmt in ipairs(block) do
        local stmt_end = max_source_line(stmt)
        if fmt_off_regions:includes_range(stmt.y, stmt_end) then
            return nil
        end
        if has_comment(lines, stmt.y, stmt_end) then
            return nil
        end
        if previous_end ~= nil and stmt.y > (previous_end as integer) + 1 then
            if not has_non_empty_line_between(
               lines, (previous_end as integer) + 1, stmt.y - 1
            ) then
                local empty_line_count = count_empty_lines_between(
                    lines, (previous_end as integer) + 1, stmt.y - 1
                )
                if empty_line_count >= 1 and #statement_layouts > 0 then
                    statement_layouts[#statement_layouts].preserve_blank_line_after = true
                else
                    return nil
                end
            end
        end
        if not stmt_is_safe_source_shape(stmt) then
            return nil
        end
        local statement_layout = StatementLayout.new()
        if stmt.body ~= nil then
            local body_layout = structural_render_analysis.analyze_block(
                stmt.body, lines, fmt_off_regions
            )
            if body_layout == nil then
                return nil
            end
            statement_layout.body_layout = body_layout
        end
        if stmt.if_blocks ~= nil then
            local if_block_layouts: {any} = {}
            for _, if_block in ipairs(stmt.if_blocks) do
                if if_block.body == nil then
                    return nil
                end
                local if_block_layout = structural_render_analysis.analyze_block(
                    if_block.body, lines, fmt_off_regions
                )
                if if_block_layout == nil then
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

function structural_render_analysis.can_render_block(
    block: parser.Node, lines: {string}, fmt_off_regions: ast_utils.FmtOffRegions
): boolean
    return structural_render_analysis.analyze_block(
       block, lines, fmt_off_regions
    ) ~= nil
end

return structural_render_analysis
