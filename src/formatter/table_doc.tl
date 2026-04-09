-- Table constructor → doc.Doc (build_table_doc) or {string} (render_table).
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local type_doc = require("formatter.type_doc")

local table_doc = {}

local function build_table_item_text(
    item: parser.Node, render_expr: function(parser.Node): doc.Doc
): doc.Doc
    if item.key_parsed == "implicit" then
        return render_expr(item.value)
    elseif item.key_parsed == "short" then
        local key_text = item.key.conststr or item.key.tk
        if item.itemtype ~= nil then
            return doc.concat(
                {
                    doc.text(key_text .. ": "),
                    type_doc.render(item.itemtype),
                    doc.text(" = "),
                    render_expr(item.value),
                }
            )
        end
        return doc.concat({doc.text(key_text .. " = "), render_expr(item.value)})
    end

    return doc.concat(
        {
            doc.text("["),
            render_expr(item.key),
            doc.text("] = "),
            render_expr(item.value),
        }
    )
end

local function build_delimited_sequence_doc(
    line_items: render_builders.CommentLineItems,
    opts: render_builders.DelimitedSequenceOptions,
    force_wrap: boolean
): doc.Doc
    local function item_suffix(
        entry: render_builders.LineEntry, is_final: boolean
    ): doc.Doc | nil
        local sep = #entry.trailing_comments > 0 and "," or ", "
        if is_final then
            return doc.if_wrapped(sep)
        end
        return doc.text(sep)
    end

    local function entry_separator(ctx: render_builders.EntrySeparatorContext): doc.Doc
        if force_wrap
            or ctx.previous_has_trailing_comments
            or ctx.next_has_leading_comments
            or ctx.next_is_comment_only then
            return doc.hardline()
        end
        return doc.softline()
    end

    local items_doc = render_builders.render_line_entries(
        line_items, item_suffix, entry_separator
    )
    if not (force_wrap or line_items.has_comments) then
        items_doc = doc.group(items_doc)
    end
    local line_doc = force_wrap and doc.hardline() or doc.softline()
    local table_doc_node = render_builders.build_delimited_body_doc(
        items_doc, opts, line_doc
    )
    if force_wrap or line_items.has_comments then
        return doc.concat({doc.break_parent(), table_doc_node})
    else
        return doc.group(table_doc_node)
    end
end

function table_doc.build_table_doc(
    node: parser.Node, render_expr: function(parser.Node): doc.Doc
): doc.Doc
    local line_items = render_builders.CommentLineItems.new()
    line_items:add_end_comments(node.end_comments or {})
    for _, item in ipairs(node) do
        line_items:add(
            build_table_item_text(item, render_expr),
            render_builders.node_effective_end_line(item),
            item.comments or {},
            false
        )
    end

    local opts = render_builders.DelimitedSequenceOptions.new("{", "}", 4)
    return build_delimited_sequence_doc(line_items, opts, node.trailing_comma)
end

return table_doc
