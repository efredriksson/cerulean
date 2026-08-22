-- Sorts contiguous top-level local require declarations alphabetically.
-- Stops at the first non-require statement or fmt:off region.
-- Operates directly on the AST, reordering nodes in-place before rendering.
--
-- Comment handling:
--   Leading comments (before a require) travel with their require.
--   Trailing comments (same-line, parser-attached to the next node) are
--   redistributed so they remain after their original require in the output.
local ast = require("cerulean.ast")
local source = require("cerulean.source")

local type Regions = source.Regions

local require_sort = {}

local record SortableRequire
    node: ast.Node
    module_path: string
end

function SortableRequire.new(node: ast.Node, module_path: string): SortableRequire
    local self: SortableRequire = setmetatable({}, {__index = SortableRequire})
    self.node = node
    self.module_path = module_path
    return self
end

local function extract_require_module_path(node: ast.Node): string | nil
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
    if call_node.kind ~= "call" then
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

-- Move a comment to line `y`, keeping the height it had, and answer the line
-- after it. Sorting relocates comments, so their source lines have to be
-- rewritten before the renderer measures blank lines against them.
local function move_comment_to(comment: ast.Comment, y: integer): integer
    local height = comment.yend - comment.y
    comment.y = y
    comment.yend = y + height
    return comment.yend + 1
end

local function separate_comments(
    node: ast.Node, comments: {ast.Comment}
): {ast.Comment}, {ast.Comment}
    local previous_y = node.y
    local floating_comments: {ast.Comment} = {}
    local attached_comments: {ast.Comment} = {}
    local entered_floating_region = false
    for i = #comments, 1, -1 do
        local comment = comments[i]
        if entered_floating_region or comment.yend < previous_y - 1 then
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

-- Reorders the contiguous top-level requires in place and returns its comment
-- placement as a render-time signal rather than mutating the comment slots the
-- renderer no longer reads. The first return is a per-node leading override (the
-- nodes require_sort relocated comments onto, read by the renderer in place of
-- the token stream): module documentation hoisted onto the sorted-first require,
-- each require's own attached comments travelling with it. The second is the
-- floating tail -- own-line comments a blank line apart from any require -- which
-- the renderer appends after the sorted block, or leads the following statement
-- when one exists (folded into that statement's override, tail then empty).
-- The pass-filled leading slots are still read as input here; only the placement
-- is redirected off them.
function require_sort.sort_top_level_requires(
    root: ast.Node,
    fmt_off_regions: Regions,
    leading_of: function(ast.Node): {ast.Comment}
): {ast.Node: {ast.Comment}}, {ast.Comment}
    local sortable: {SortableRequire} = {}

    for _, node in ipairs(root) do
        local node_end = node.yend
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
        return {}, {}
    end

    local current_y = 1

    -- Detach top-level comments, these are module comments and
    -- are not considered attached to statements during sorting
    local float_module_documentation = {}
    local attach_module_documentation = {}

    local overrides: {ast.Node: {ast.Comment}} = {}
    local own_attached: {ast.Node: {ast.Comment}} = {}
    local all_floating_comments: {ast.Comment} = {}
    for index, entry in ipairs(sortable) do
        local attached_comments, floating_comments = separate_comments(
            entry.node, leading_of(entry.node)
        )
        own_attached[entry.node] = attached_comments

        if index == 1 then
            if #floating_comments == 0 then
                -- If there are no floating comments then assume the attched comment
                -- is intended as the module comment
                attach_module_documentation = attached_comments
                own_attached[entry.node] = {}
            else
                float_module_documentation = floating_comments
            end
        else
            for _, floating_comment in ipairs(floating_comments) do
                table.insert(all_floating_comments, floating_comment)
            end
        end
    end

    table.sort(sortable, by_module_path)
    local first_require_stmt = sortable[1].node
    first_require_stmt.blank_line_before = true

    -- TODO: Need to refactor all these for loops so things
    -- can be read in a more declarative way!
    local total_top_level_comments: {ast.Comment} = {}
    for _, comment in ipairs(float_module_documentation) do
        table.insert(total_top_level_comments, comment)
        current_y = comment.yend + 2
    end
    for _, comment in ipairs(attach_module_documentation) do
        table.insert(total_top_level_comments, comment)
        current_y = comment.yend + 1
        first_require_stmt.blank_line_before = false
    end
    for index, comment in ipairs(own_attached[first_require_stmt] or {}) do
        if index == 1 and #attach_module_documentation == 0 then
            comment.blank_line_before = true
        end
        current_y = move_comment_to(comment, current_y)
        table.insert(total_top_level_comments, comment)
        first_require_stmt.blank_line_before = false
    end
    overrides[first_require_stmt] = total_top_level_comments
    if #total_top_level_comments == 0 then
        first_require_stmt.blank_line_before = false
    end

    for index, entry in ipairs(sortable) do
        if index ~= 1 then
            local entry_leading = own_attached[entry.node] or {}
            for _, comment in ipairs(entry_leading) do
                current_y = move_comment_to(comment, current_y)
            end
            overrides[entry.node] = entry_leading
            entry.node.blank_line_before = false
        end

        local node_len = entry.node.yend - entry.node.y
        entry.node.y = current_y
        entry.node.yend = current_y + node_len
        root[index] = entry.node
        current_y = entry.node.yend + 1
    end

    for index, comment in ipairs(all_floating_comments) do
        if index == 1 then
            comment.blank_line_before = true
            current_y = current_y + 1
        end

        current_y = move_comment_to(comment, current_y)
    end

    local next_stmt = root[count + 1]
    if next_stmt then
        for _, comment in ipairs(leading_of(next_stmt)) do
            table.insert(all_floating_comments, comment)
        end
        overrides[next_stmt] = all_floating_comments
        return overrides, {}
    end
    return overrides, all_floating_comments
end

return require_sort
