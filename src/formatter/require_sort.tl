-- Sorts contiguous top-level local require declarations alphabetically.
-- Stops at the first non-require statement or fmt:off region.
-- Operates directly on the AST, reordering nodes in-place before rendering.
--
-- Comment handling:
--   Leading comments (before a require) travel with their require.
--   Trailing comments (same-line, parser-attached to the next node) are
--   redistributed so they remain after their original require in the output.
local parser = require("formatter.parser")
local source = require("formatter.source")

local type Regions = source.Regions

local require_sort = {}

local record SortableRequire
    node: parser.Node
    module_path: string
end

function SortableRequire.new(node: parser.Node, module_path: string): SortableRequire
    local self: SortableRequire = setmetatable({}, {__index = SortableRequire})
    self.node = node
    self.module_path = module_path
    return self
end

local function extract_require_module_path(node: parser.Node): string | nil
    if node.kind ~= "local_declaration" then
        return nil
    end
    if node.vars == nil or #node.vars ~= 1 then
        return nil
    end
    if node.exps == nil or #node.exps ~= 1 then
        return nil
    end
    local call_node = node.exps[1]
    if call_node == nil then
        return nil
    end
    if call_node.kind ~= "op" then
        return nil
    end
    if call_node.op == nil or call_node.op.op ~= "@funcall" then
        return nil
    end
    if call_node.e1 == nil or call_node.e1.tk ~= "require" then
        return nil
    end
    if call_node.e2 == nil or #call_node.e2 ~= 1 then
        return nil
    end
    local string_arg = call_node.e2[1]
    if string_arg == nil or string_arg.kind ~= "string" then
        return nil
    end
    return string_arg.conststr or ""
end

local function by_module_path(first: SortableRequire, second: SortableRequire): boolean
    return first.module_path < second.module_path
end

local function comment_len(comment: parser.Comment): integer
    local _, comment_line_breaks = comment.text:gsub("\n", "\n")
    return comment_line_breaks + 1
end

local function comment_yend(comment: parser.Comment): integer
    return comment.y + comment_len(comment) - 1
end

local function separate_comments(node: parser.Node): {parser.Comment}, {parser.Comment}
    local comments = node.comments or {}
    local previous_y = node.y
    local floating_comments: {parser.Comment} = {}
    local attached_comments: {parser.Comment} = {}
    local entered_floating_region = false
    for i = #comments, 1, -1 do
        local comment = comments[i]
        if entered_floating_region or comment_yend(comment) < previous_y - 1 then
            entered_floating_region = true
            table.insert(floating_comments, 1, comment)
        else
            comment.blank_line_before = false
            table.insert(attached_comments, 1, comment)
        end
        previous_y = comment.y
    end

    return attached_comments, floating_comments
end

function require_sort.sort_top_level_requires(
    ast: parser.Node, fmt_off_regions: Regions
)
    local sortable: {SortableRequire} = {}

    for _, node in ipairs(ast) do
        local node_end = node.yend or node.y
        if fmt_off_regions:includes_range(node.y, node_end) then
            break
        end
        local module_path = extract_require_module_path(node)
        if module_path == nil then
            break
        end
        table.insert(sortable, SortableRequire.new(node, module_path))
    end

    local count = #sortable
    if count <= 1 then
        return
    end

    local current_y = 1

    -- Detach top-level comments, these are module comments and
    -- are not considered attached to statements during sorting
    local float_module_documentation = {}
    local attach_module_documentation = {}

    local all_floating_comments: {parser.Comment} = {}
    for index, entry in ipairs(sortable) do
        local attached_comments, floating_comments = separate_comments(entry.node)

        if index == 1 then
            if #floating_comments == 0 then
                -- If there are no floating comments then assume the attched comment
                -- is intended as the module comment
                attach_module_documentation = attached_comments
                entry.node.comments = {}
            else
                float_module_documentation = floating_comments
                entry.node.comments = attached_comments
            end
        else
            entry.node.comments = attached_comments
            for _, floating_comment in ipairs(floating_comments) do
                table.insert(all_floating_comments, floating_comment)
            end
        end
    end

    table.sort(sortable, by_module_path)

    -- TODO: Need to refactor all these for loops so things
    -- can be read in a more declarative way!
    local total_top_level_comments: {parser.Comment} = {}
    for _, comment in ipairs(float_module_documentation) do
        table.insert(total_top_level_comments, comment)
        current_y = comment_yend(comment) + 2
    end
    for _, comment in ipairs(attach_module_documentation) do
        table.insert(total_top_level_comments, comment)
        current_y = comment_yend(comment) + 1
    end
    for index, comment in ipairs(sortable[1].node.comments) do
        if index == 1 and #attach_module_documentation == 0 then
            comment.blank_line_before = true
        end
        comment.y = current_y
        table.insert(total_top_level_comments, comment)
        current_y = comment_yend(comment) + 1
    end
    sortable[1].node.comments = total_top_level_comments

    for index, entry in ipairs(sortable) do
        if index ~= 1 then
            for _, comment in ipairs(entry.node.comments or {}) do
                comment.y = current_y
                current_y = current_y + comment_len(comment)
            end
        end

        local node_len = entry.node.yend or entry.node.y - entry.node.y
        entry.node.y = current_y
        entry.node.yend = current_y + node_len
        ast[index] = entry.node
        current_y = entry.node.yend + 1
    end

    for index, comment in ipairs(all_floating_comments) do
        if index == 1 then
            comment.blank_line_before = true
            current_y = current_y + 1
        end

        comment.y = current_y
        current_y = current_y + 1
    end

    local next_stmt = ast[count + 1]
    if next_stmt then
        for _, comment in ipairs(next_stmt.comments or {}) do
            table.insert(all_floating_comments, comment)
        end
        next_stmt.comments = all_floating_comments
    else
        for _, comment in ipairs(ast.end_comments or {}) do
            table.insert(all_floating_comments, comment)
        end
        ast.end_comments = all_floating_comments
    end
end

return require_sort
