-- Comma-separated, comment-threaded list → doc.Doc.
local ast = require("cerulean.ast")
local construct_layout = require("cerulean.construct_layout")
local doc = require("cerulean.doc")
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

function delimited_list_doc.build_comma_line_item_docs(item_docs: {doc.Doc}): doc.Doc
    local parts: {doc.Doc} = {}

    for index, item_doc in ipairs(item_docs) do
        table.insert(parts, item_doc)
        if index < #item_docs then
            table.insert(parts, doc.text(","))
            table.insert(parts, doc.line())
        end
    end

    return doc.concat(parts)
end

-- Every comma gives at once: the list is one line or one item per line, never a
-- ragged fill. Shared by delimited sequences and `=` value lists.
function delimited_list_doc.build_grouped_comma_items_doc(item_docs: {doc.Doc}): doc.Doc
    return doc.group(delimited_list_doc.build_comma_line_item_docs(item_docs))
end

function delimited_list_doc.build_separated_docs(
    item_docs: {doc.Doc}, separator: string
): doc.Doc
    local parts: {doc.Doc} = {}
    for index, item_doc in ipairs(item_docs) do
        table.insert(parts, item_doc)
        if index < #item_docs then
            table.insert(parts, doc.text(separator))
        end
    end
    return doc.concat(parts)
end

function delimited_list_doc.build_comma_separated_docs(item_docs: {doc.Doc}): doc.Doc
    return delimited_list_doc.build_separated_docs(item_docs, ", ")
end

local function mapped_exp_docs(ctx: RenderContext, nodes: {ast.Node}): {doc.Doc}
    local item_docs: {doc.Doc} = {}
    for _, node in ipairs(nodes) do
        table.insert(item_docs, ctx.render_expr(node))
    end
    return item_docs
end

function delimited_list_doc.build_mapped_comma_separated_docs(
    ctx: RenderContext, nodes: {ast.Node}
): doc.Doc
    return delimited_list_doc.build_comma_separated_docs(mapped_exp_docs(ctx, nodes))
end

-- A threaded comment pins its item to a line of its own, so the commas stop being
-- free break points and the list has to render through the comment path.
function delimited_list_doc.exp_list_can_break(
    ctx: RenderContext, exps: {ast.Node}
): boolean
    return #exps > 1 and not construct_layout.any_items_have_comments(ctx, exps, false)
end

-- The first item's own-line comments lead the whole statement, so the enclosing block
-- emits those; only a continuation item reads its own.
local function continuation_leading_comments(
    ctx: RenderContext, items: {ast.Node}, index: integer
): {ast.Comment}
    if index == 1 then
        return {}
    end
    return ctx.slots:item_leading_comments(items[index], items[index - 1], false)
end

local function with_own_line_comments(
    comments: {ast.Comment}, item_doc: doc.Doc
): doc.Doc
    local parts: {doc.Doc} = {}
    trivia_doc.append_comment_docs(parts, comments, false)
    table.insert(parts, doc.hardline())
    table.insert(parts, item_doc)
    return doc.concat(parts)
end

-- Join pre-rendered list items with ", ", but when a non-last item carries a
-- trailing comment (a line comment after it or its separator) emit the comma, the
-- comment, and a hardline so the next item starts on its own line. An item's own-line
-- leading comments open that line too, which is where the trailing run parks the
-- comments that could not stay on the separator's line. Callers that can render their
-- items through ctx.render_expr use build_exp_list_doc; this one takes pre-rendered
-- docs for lists whose items carry syntax render_expr does not (a variable list's
-- `<const>` attributes), so the caller owns item rendering and this owns the
-- separators + per-item leading and trailing.
function delimited_list_doc.build_comma_separated_with_trailing(
    ctx: RenderContext, items: {ast.Node}, item_docs: {doc.Doc}
): doc.Doc
    local parts: {doc.Doc} = {}
    local force_next_indent = false
    for index, item_doc in ipairs(item_docs) do
        local leading = continuation_leading_comments(ctx, items, index)
        local rendered = item_doc
        if #leading > 0 then
            rendered = with_own_line_comments(leading, rendered)
        end
        if force_next_indent or #leading > 0 then
            rendered = doc.indent_hardline(rendered)
        end
        force_next_indent = false
        if index < #item_docs then
            local trailing = ctx.slots:trailing_comments(items[index])
            if #trailing > 0 then
                rendered = doc.concat(
                    {
                        rendered,
                        doc.text(","),
                        trivia_doc.trailing_comment_doc(trailing, true),
                    }
                )
                force_next_indent = true
            else
                rendered = doc.concat({rendered, doc.text(", ")})
            end
        end
        table.insert(parts, rendered)
    end
    return doc.concat(parts)
end

function delimited_list_doc.build_exp_list_doc(
    ctx: RenderContext, exps: {ast.Node}
): doc.Doc
    if not construct_layout.any_items_have_comments(ctx, exps, false) then
        return delimited_list_doc.build_grouped_comma_items_doc(
            mapped_exp_docs(ctx, exps)
        )
    end
    local item_docs: {doc.Doc} = {}
    for _, exp in ipairs(exps) do
        table.insert(item_docs, ctx.render_expr(exp))
    end
    return delimited_list_doc.build_comma_separated_with_trailing(ctx, exps, item_docs)
end

-- The first value stays on the `return` line: unlike an `=` list there is no
-- operator to its left to give first, so only the continuations indent.
function delimited_list_doc.build_return_exp_list_doc(
    ctx: RenderContext, exps: {ast.Node}
): doc.Doc
    if not delimited_list_doc.exp_list_can_break(ctx, exps) then
        return delimited_list_doc.build_exp_list_doc(ctx, exps)
    end
    local item_docs = mapped_exp_docs(ctx, exps)
    -- Outside the indent, so only the continuations shift right.
    local first_doc = table.remove(item_docs, 1)
    local continuations = doc.concat(
        {
            doc.text(","),
            doc.line(),
            delimited_list_doc.build_comma_line_item_docs(item_docs),
        }
    )
    return doc.concat({first_doc, doc.group(doc.indent(continuations))})
end

function delimited_list_doc.item_line_doc(should_force_wrap: boolean): doc.Doc
    if should_force_wrap then
        return doc.hardline()
    else
        return doc.softline()
    end
end

function delimited_list_doc.append_lines_pre_node(
    node: ast.Node | ast.FieldEntry,
    line_before: boolean,
    line_from_before?: doc.Doc,
    suppress_blank?: boolean
): doc.Doc
    local parts: {doc.Doc} = {}
    if line_before then
        table.insert(parts, line_from_before or doc.softline())
    end
    if node.blank_line_before and not suppress_blank then
        -- enclosing group MUST break, for example anon function.
        table.insert(parts, doc.concat({doc.hardline(), doc.break_parent()}))
    end

    return doc.concat(parts)
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
        line_before = trivia_doc.append_comment_docs(parts, item_leading, line_before)
        local suppress_blank = not spec.force_wrap
        local pre_item_doc = delimited_list_doc.append_lines_pre_node(
            item, line_before, nil, suppress_blank
        )
        table.insert(parts, pre_item_doc)
        table.insert(parts, spec.render_item(item))
        table.insert(parts, spec.make_separator(item, index == #item_nodes))
        local item_trailing: {ast.Comment} = {}
        if not (spec.exclude_last_trailing and index == #item_nodes) then
            item_trailing = ctx.slots:trailing_comments(item)
        end
        table.insert(parts, trivia_doc.trailing_comment_doc(item_trailing))
        line_before = true
    end
    trivia_doc.append_comment_docs(parts, dangling, line_before)

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
    local force_wrap = construct_layout.any_items_have_comments(
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
