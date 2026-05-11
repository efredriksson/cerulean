-- Table constructor → doc.Doc (build_table_doc) or {string} (render_table).
local doc = require("cerulean.doc")
local parser = require("cerulean.parser")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local trivia_doc = require("cerulean.trivia_doc")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local table_doc = {}

-- In `expr as function(args): T`, the trailing `,` after the cast is parsed as
-- a return-type separator for the function type, breaking the next table field.
-- Using `;` instead of `,` avoids the ambiguity. A non-cast binary parent does
-- not parenthesize its right operand around a cast (the cast renderer skips
-- precedence parens), so walk through binary `e2` to find a rightmost cast.
-- Unary prefixes always parenthesize a lower-prec operand, so they cannot leave
-- a cast at the tail and are not walked into.
local function item_value_needs_semicolon(value: parser.Node): boolean
    while value.kind == "op" and value.op.arity == 2 do
        local op = value.op.op
        if op == "as" or op == "is" then
            return type_doc.cast_absorbs_trailing_comma(value.e2.casttype)
        end
        if op == "@funcall" or op == "@index" or op == "." or op == ":" then
            return false
        end
        value = value.e2
    end
    return false
end

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
        return render_builders.with_leading_inline_trivia(
            item, doc.text(key_text .. " = "), ctx.render_expr(item.value)
        )
    end

    local bracket_spacing = render_builders.key_starts_with_long_string(item.key)
        and " " or ""
    return doc.concat(
        {
            doc.text("[" .. bracket_spacing),
            ctx.render_expr(item.key),
            doc.text(bracket_spacing .. "] = "),
            ctx.render_expr(item.value),
        }
    )
end

local function has_any_comments(items: parser.Node): boolean
    return render_builders.any_items_have_comments(items)
        or items.trailing_comma
        or #(items.dangling_comments or {}) > 0
end

function table_doc.build_table_doc(
    ctx: RenderContext, items: parser.Node, separator_char?: string
): doc.Doc
    local force_wrap = has_any_comments(items)
    local line_doc = render_builders.item_line_doc(force_wrap)
    local parts: {doc.Doc} = {}
    local sep_char = separator_char or ","

    local line_before = false
    for index, item in ipairs(items) do
        line_before = render_builders.append_comment_docs(
            parts, item.leading_comments or {}, line_before
        )

        table.insert(parts, render_builders.append_lines_pre_node(item, line_before))
        table.insert(parts, build_table_item_text(ctx, item))
        trivia_doc.append_inline(parts, item.trailing_trivia)

        local effective_sep = (item_value_needs_semicolon(item.value) and ";")
            or sep_char
        local sep = item.trailing_comment and effective_sep or effective_sep .. " "
        if index < #items then
            table.insert(parts, doc.text(sep))
        else
            table.insert(parts, doc.if_wrapped(sep))
        end

        table.insert(parts, render_builders.trailing_comment_doc(item))
        line_before = true
    end

    render_builders.append_comment_docs(
        parts, items.dangling_comments or {}, line_before
    )

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
