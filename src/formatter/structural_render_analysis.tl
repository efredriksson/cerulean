local ast_utils = require("formatter.ast_utils")
local parser = require("formatter.parser")

local structural_render_analysis = {}

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

local function stmt_is_safe_source_shape(stmt: parser.Node): boolean
    if stmt.kind == "return" then
        return true
    elseif stmt.kind == "assignment" then
        return true
    elseif stmt.kind == "local_declaration" then
        return true
    elseif stmt.kind == "local_type" then
        return stmt.value ~= nil
    elseif stmt.kind == "op" then
        return node_is_single_line(stmt)
    elseif stmt.kind == "break" then
        return true
    elseif stmt.kind == "local_function" or stmt.kind == "global_function" then
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

function structural_render_analysis.can_render_block(
    block: parser.Node, lines: {string}, fmt_off_regions: ast_utils.FmtOffRegions
): boolean
    if #block == 0 then
        return false
    end

    local previous_end: integer | nil = nil
    for _, stmt in ipairs(block) do
        local stmt_end = max_source_line(stmt)
        if fmt_off_regions:includes_range(stmt.y, stmt_end) then
            return false
        end
        if has_comment(lines, stmt.y, stmt_end) then
            return false
        end
        if previous_end ~= nil and stmt.y > (previous_end as integer) + 1 then
            if not has_non_empty_line_between(
               lines, (previous_end as integer) + 1, stmt.y - 1
            ) then
                return false
            end
        end
        if not stmt_is_safe_source_shape(stmt) then
            return false
        end
        if stmt.body ~= nil and not structural_render_analysis.can_render_block(
           stmt.body, lines, fmt_off_regions
        ) then
            return false
        end
        if stmt.if_blocks ~= nil then
            for _, if_block in ipairs(stmt.if_blocks) do
                if if_block.body == nil then
                    return false
                end
                if not structural_render_analysis.can_render_block(
                   if_block.body, lines, fmt_off_regions
                ) then
                    return false
                end
            end
        end
        previous_end = stmt_end
    end

    return true
end

return structural_render_analysis
