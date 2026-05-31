-- Parenthesized, comma-separated list → doc.Doc.
local doc = require("cerulean.doc")
local parser = require("cerulean.parser")
local render_builders = require("cerulean.render_builders")
local trivia_doc = require("cerulean.trivia_doc")

local paren_list_doc = {}

-- Renders a parenthesized, comma-separated list (no trailing comma) with full
-- comment threading. This is the single renderer behind both function-call
-- argument lists (expr_doc) and function parameter lists (signature_doc), so the
-- two can't drift. One loop threads each item's leading/trailing/before-separator
-- comments, dangling comments are emitted before the closing paren, and a comment
-- on the opener line (`after_opener`) trails the `(`. Any comment forces a wrap.
--
-- Callers supply the pre-filtered `item_nodes` and a `render_item` that produces
-- an item's core doc; `list_node` is the spanning node carrying the `after_opener`
-- inline trivia and `dangling_comments` slots around the parens.
function paren_list_doc.render(
    list_node: parser.Node,
    item_nodes: {parser.Node},
    render_item: function(parser.Node): doc.Doc
): doc.Doc
    local after_opener = parser.inline_trivia(list_node, "after_opener")
    local dangling = list_node.dangling_comments or {}
    local force_wrap = render_builders.any_items_have_comments(list_node)
        or #after_opener > 0
        or #dangling > 0

    local parts: {doc.Doc} = {}
    local line_before = false
    for index, item in ipairs(item_nodes) do
        line_before = render_builders.append_comment_docs(
            parts, item.leading_comments or {}, line_before
        )
        table.insert(parts, render_builders.append_lines_pre_node(item, line_before))
        local item_parts: {doc.Doc} = {render_item(item)}
        trivia_doc.append_inline(
            item_parts, parser.inline_trivia(item, "before_separator")
        )
        if index < #item_nodes then
            local has_trailing = #(item.trailing_comments or {}) > 0
            table.insert(item_parts, doc.text(has_trailing and "," or ", "))
        end
        table.insert(parts, doc.concat(item_parts))
        table.insert(parts, render_builders.trailing_comment_doc(item))
        line_before = true
    end
    render_builders.append_comment_docs(parts, dangling, line_before)

    local items_doc = doc.concat(parts)
    if not force_wrap then
        items_doc = doc.group(items_doc)
    end

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

return paren_list_doc
