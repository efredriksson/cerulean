-- Table constructor → doc.Doc (build_table_doc) or {string} (render_table).
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local render_context = require("formatter.render_context")
local type_doc = require("formatter.type_doc")

local type RenderContext = render_context.RenderContext

local table_doc = {}

local function build_table_item_text(ctx: RenderContext, item: parser.Node): doc.Doc
    if item.key_parsed == "implicit" then
        return ctx.render_expr(item.value)
    elseif item.key_parsed == "short" then
        local key_text = item.key.conststr or item.key.tk
        if item.itemtype ~= nil then
            return doc.concat(
                {
                    doc.text(key_text .. ": "),
                    type_doc.render(item.itemtype),
                    doc.text(" = "),
                    ctx.render_expr(item.value),
                }
            )
        end
        return doc.concat({doc.text(key_text .. " = "), ctx.render_expr(item.value)})
    end

    return doc.concat(
        {
            doc.text("["),
            ctx.render_expr(item.key),
            doc.text("] = "),
            ctx.render_expr(item.value),
        }
    )
end

local function has_any_comments(items: parser.Node): boolean
    return render_builders.any_items_have_comments(items)
        or items.trailing_comma
        or #(items.end_comments or {}) > 0
end

function table_doc.build_table_doc(ctx: RenderContext, items: parser.Node): doc.Doc
    local force_wrap = has_any_comments(items)
    local line_doc = render_builders.item_line_doc(force_wrap)
    local parts: {doc.Doc} = {}

    local line_before = false
    for index, item in ipairs(items) do
        for _, comment in ipairs(item.comments or {}) do
            if line_before then
                table.insert(parts, doc.hardline())
            end
            if comment.blank_line_before then
                table.insert(parts, doc.hardline())
            end
            table.insert(parts, doc.text(comment.text))
            line_before = true
        end
        if line_before then
            table.insert(parts, line_doc)
        end
        if item.blank_line_before then
            table.insert(parts, doc.hardline())
        end

        table.insert(parts, build_table_item_text(ctx, item))

        local sep = item.trailing_comment and "," or ", "
        if index < #items then
            table.insert(parts, doc.text(sep))
        else
            table.insert(parts, doc.if_wrapped(sep))
        end

        table.insert(parts, render_builders.trailing_comment_doc(item))
        line_before = true
    end

    for _, comment in ipairs(items.end_comments or {}) do
        if line_before then
            table.insert(parts, doc.hardline())
        end
        if comment.blank_line_before then
            table.insert(parts, doc.hardline())
        end
        table.insert(parts, doc.text(comment.text))
        line_before = true
    end

    local items_doc = doc.concat(parts)
    if not force_wrap then
        items_doc = doc.group(items_doc)
    end
    local table_body_doc = doc.concat(
        {
            doc.text("{"),
            doc.indent(doc.concat({line_doc, items_doc})),
            line_doc,
            doc.text("}"),
        }
    )
    if force_wrap then
        return doc.concat({doc.break_parent(), table_body_doc})
    else
        return doc.group(table_body_doc)
    end
end

return table_doc
