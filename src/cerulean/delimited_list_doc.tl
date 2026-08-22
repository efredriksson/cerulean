-- Comma-separated, comment-threaded list → doc.Doc.
local ast = require("cerulean.ast")
local doc = require("cerulean.doc")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local trivia_doc = require("cerulean.trivia_doc")

local type RenderContext = render_context.RenderContext

local type RenderItem = function(ast.Node): doc.Doc
-- `is_last` lets table-style lists add a trailing comma that paren lists omit.
local type MakeSeparator = function(ast.Node, boolean): doc.Doc

local record ItemRenderSpec
    force_wrap: boolean
    render_item: RenderItem
    make_separator: MakeSeparator
    -- Whether the first item absorbs a same-line comment trailing the container's
    -- opener (true for tables, false for parenthesized lists, which carry it in
    -- the list's after_opener slot). See RenderContext:item_leading_comments.
    absorb_first_opener: boolean
    -- Whether the last item's own trailing-comment read must be skipped: for a
    -- sugar call (`t{}`, `t"s"`) the sole argument has no closing token of its
    -- own, so its last token is also the call's, and that trailing comment is
    -- the call's own -- read and rendered outside this list (see render_parens).
    exclude_last_trailing: boolean
    new: function(boolean, RenderItem, MakeSeparator, boolean, ?boolean): ItemRenderSpec
end

local delimited_list_doc = {
    ItemRenderSpec = ItemRenderSpec,
}

function ItemRenderSpec.new(
    force_wrap: boolean,
    render_item: RenderItem,
    make_separator: MakeSeparator,
    absorb_first_opener: boolean,
    exclude_last_trailing?: boolean
): ItemRenderSpec
    local self: ItemRenderSpec = setmetatable({}, {__index = ItemRenderSpec})
    self.force_wrap = force_wrap
    self.render_item = render_item
    self.make_separator = make_separator
    self.absorb_first_opener = absorb_first_opener
    self.exclude_last_trailing = exclude_last_trailing or false
    return self
end

-- The framing-agnostic item loop shared by every delimited list, so their comment
-- handling can't drift. Grouped unless the spec forces a wrap.
function delimited_list_doc.render_items(
    ctx: RenderContext,
    item_nodes: {ast.Node},
    dangling: {ast.Comment},
    spec: ItemRenderSpec
): doc.Doc
    local parts: {doc.Doc} = {}
    local line_before = false
    for index, item in ipairs(item_nodes) do
        -- A `statements` item is a block (a macro's `Statement` argument is the
        -- only list item shaped like one) and a block owns every comment between
        -- its own bounds, so reading its leading here would emit it twice.
        local item_leading: {ast.Comment} = {}
        if item.kind ~= "statements" then
            item_leading = ctx.slots:item_leading_comments(
                item, item_nodes[index - 1], index == 1 and spec.absorb_first_opener
            )
        end
        line_before = render_builders.append_comment_docs(
            parts, item_leading, line_before
        )
        local suppress_blank = not spec.force_wrap
        local pre_item_doc = render_builders.append_lines_pre_node(
            item, line_before, nil, suppress_blank
        )
        table.insert(parts, pre_item_doc)
        table.insert(parts, spec.render_item(item))
        table.insert(parts, spec.make_separator(item, index == #item_nodes))
        local item_trailing: {ast.Comment} = {}
        if not (spec.exclude_last_trailing and index == #item_nodes) then
            item_trailing = ctx.slots:trailing_comments(item)
        end
        table.insert(parts, render_builders.trailing_comment_doc(item_trailing))
        line_before = true
    end
    render_builders.append_comment_docs(parts, dangling, line_before)

    local items_doc = doc.concat(parts)
    if not spec.force_wrap then
        items_doc = doc.group(items_doc)
    end
    return items_doc
end

-- Frames the shared item loop in parens, for call argument lists and parameter
-- lists. `item_nodes` must be pre-filtered to the real entries; `list_node` is the
-- spanning node carrying the `after_opener` trivia (a comment on the opener line,
-- which trails the `(`) and the dangling comments before `)`.
function delimited_list_doc.render_parens(
    ctx: RenderContext,
    list_node: ast.Node,
    item_nodes: {ast.Node},
    render_item: RenderItem
): doc.Doc
    -- A sugar call (`t{}`, `t"s"`) never opens real parens, so the parser never
    -- stamps an after_opener slot for it; its sole argument's last token doubles
    -- as the call's own, so that argument must yield its trailing comment to the
    -- call (rendered outside these synthesized parens) rather than claim it here.
    local is_sugar_call = list_node.slot_tok == nil
        or list_node.slot_tok["after_opener"] == nil
    local after_opener = ctx.slots:opener_comments(list_node, "after_opener")
    -- A trailing `statements` item runs to the closer, so the comments before `)`
    -- are inside that block and it renders them as its own dangling.
    local last_item = item_nodes[#item_nodes]
    local dangling: {ast.Comment} = {}
    if last_item == nil or last_item.kind ~= "statements" then
        dangling = ctx.slots:container_dangling_comments(list_node)
    end
    local force_wrap = render_builders.any_items_have_comments(
        ctx, list_node, false, is_sugar_call
    ) or #after_opener > 0
        or #dangling > 0

    -- An empty list has nothing to split, so it offers no break point: its
    -- softlines would read as a place for the line to end and draw the break
    -- into `(` when nothing else can move. With zero items, `not force_wrap`
    -- means exactly "no comments in the parens", so the two reads above
    -- consumed nothing.
    if #item_nodes == 0 and not force_wrap then
        return doc.text("()")
    end

    local function paren_separator(item: ast.Node, is_last: boolean): doc.Doc
        if is_last then
            return doc.text("")
        end
        local has_trailing = #ctx.slots:trailing_comments(item) > 0
        return doc.text(has_trailing and "," or ", ")
    end

    local items_doc = delimited_list_doc.render_items(
        ctx,
        item_nodes,
        dangling,
        ItemRenderSpec.new(
            force_wrap, render_item, paren_separator, false, is_sugar_call
        )
    )

    local function build_body(): doc.Doc
        local items_trimmed = doc.trim_lines(items_doc)
        local body_parts: {doc.Doc} = {doc.text("(")}
        if #after_opener > 0 then
            trivia_doc.append_inline(body_parts, after_opener)
            table.insert(body_parts, doc.indent_hardline(items_trimmed))
        else
            table.insert(body_parts, doc.indent_softline(items_trimmed))
        end
        table.insert(body_parts, doc.softclose(")"))
        return doc.concat(body_parts)
    end

    local body = build_body()
    if force_wrap then
        return doc.concat({doc.break_parent(), body})
    end
    return doc.group(body)
end

return delimited_list_doc
