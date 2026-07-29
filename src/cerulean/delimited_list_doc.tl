-- Comma-separated, comment-threaded list → doc.Doc.
local doc = require("cerulean.doc")
local parser = require("cerulean.parser")
local render_builders = require("cerulean.render_builders")
local trivia_doc = require("cerulean.trivia_doc")

local type RenderItem = function(parser.Node): doc.Doc
-- `is_last` lets table-style lists add a trailing comma that paren lists omit.
local type MakeSeparator = function(parser.Node, boolean): doc.Doc

local record ItemRenderSpec
    force_wrap: boolean
    render_item: RenderItem
    make_separator: MakeSeparator
    new: function(boolean, RenderItem, MakeSeparator): ItemRenderSpec
end

local delimited_list_doc = {
    ItemRenderSpec = ItemRenderSpec,
}

function ItemRenderSpec.new(
    force_wrap: boolean, render_item: RenderItem, make_separator: MakeSeparator
): ItemRenderSpec
    local self: ItemRenderSpec = setmetatable({}, {__index = ItemRenderSpec})
    self.force_wrap = force_wrap
    self.render_item = render_item
    self.make_separator = make_separator
    return self
end

-- The framing-agnostic item loop shared by every delimited list, so their comment
-- handling can't drift. Grouped unless the spec forces a wrap.
function delimited_list_doc.render_items(
    item_nodes: {parser.Node}, dangling: {parser.Comment}, spec: ItemRenderSpec
): doc.Doc
    local parts: {doc.Doc} = {}
    local line_before = false
    for index, item in ipairs(item_nodes) do
        line_before = render_builders.append_comment_docs(
            parts, item.leading_comments or {}, line_before
        )
        local suppress_blank = not spec.force_wrap
        local pre_item_doc = render_builders.append_lines_pre_node(
            item, line_before, nil, suppress_blank
        )
        table.insert(parts, pre_item_doc)
        local item_parts: {doc.Doc} = {}
        trivia_doc.append_leading(item_parts, parser.inline_trivia(item, "leading"))
        table.insert(item_parts, spec.render_item(item))
        trivia_doc.append_inline(
            item_parts, parser.inline_trivia(item, "before_separator")
        )
        table.insert(item_parts, spec.make_separator(item, index == #item_nodes))
        table.insert(parts, doc.concat(item_parts))
        table.insert(parts, render_builders.trailing_comment_doc(item))
        line_before = true
    end
    render_builders.append_comment_docs(parts, dangling, line_before)

    local items_doc = doc.concat(parts)
    if not spec.force_wrap then
        items_doc = doc.group(items_doc)
    end
    return items_doc
end

local function paren_separator(item: parser.Node, is_last: boolean): doc.Doc
    if is_last then
        return doc.text("")
    end
    local has_trailing = #(item.trailing_comments or {}) > 0
    return doc.text(has_trailing and "," or ", ")
end

-- Frames the shared item loop in parens, for call argument lists and parameter
-- lists. `item_nodes` must be pre-filtered to the real entries; `list_node` is the
-- spanning node carrying the `after_opener` trivia (a comment on the opener line,
-- which trails the `(`) and the `dangling_comments` before `)`.
function delimited_list_doc.render_parens(
    list_node: parser.Node,
    item_nodes: {parser.Node},
    render_item: RenderItem,
    hug_single?: boolean
): doc.Doc
    local after_opener = parser.inline_trivia(list_node, "after_opener")
    local dangling = list_node.dangling_comments or {}
    local force_wrap = render_builders.any_items_have_comments(list_node)
        or #after_opener > 0
        or #dangling > 0

    local items_doc = delimited_list_doc.render_items(
        item_nodes,
        dangling,
        ItemRenderSpec.new(force_wrap, render_item, paren_separator)
    )

    local function build_body(): doc.Doc
        local items_for_body = hug_single and items_doc or doc.trim_lines(items_doc)
        local body_parts: {doc.Doc} = {doc.text("(")}
        if #after_opener > 0 then
            trivia_doc.append_inline(body_parts, after_opener)
            table.insert(body_parts, doc.indent_hardline(items_for_body))
        elseif hug_single then
            table.insert(body_parts, items_for_body)
        else
            table.insert(body_parts, doc.indent_softline(items_for_body))
        end
        table.insert(body_parts, hug_single and doc.text(")") or doc.softclose(")"))
        return doc.concat(body_parts)
    end

    local body = build_body()
    if force_wrap then
        return doc.concat({doc.break_parent(), body})
    end
    return doc.group(body)
end

return delimited_list_doc
