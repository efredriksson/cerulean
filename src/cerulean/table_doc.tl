-- Table constructor → doc.Doc (build_table_doc) or {string} (render_table).
local delimited_list_doc = require("cerulean.delimited_list_doc")
local doc = require("cerulean.doc")
local parser = require("cerulean.parser")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext
local type ItemRenderSpec = delimited_list_doc.ItemRenderSpec

local table_doc = {}

local function binary_right_gets_parens(
    child: parser.Node, parent_prec: integer
): boolean
    if child.kind ~= "op" then
        return false
    end
    local op = child.op.op
    if op == "as" or op == "is" then
        return false
    end
    return child.op.prec < parent_prec
end

-- `x as function(): T, next` re-parses as `x as function(): (T, next)`: the table
-- separator `,` is greedily consumed as a return-type component. Use `;` instead.
-- Walks the rightmost operand chain to find such a cast, stopping when the
-- renderer would already wrap the subtree in parens, making the `,` safe.
local function item_value_needs_semicolon(value: parser.Node): boolean
    while value.kind == "op" do
        if value.op.arity == 2 then
            local op = value.op.op
            if op == "as" or op == "is" then
                return type_doc.cast_absorbs_trailing_comma(value.e2.casttype)
            end
            if op == "@funcall" or op == "@index" or op == "." or op == ":" then
                return false
            end
            local parent_prec = value.op.prec
            value = value.e2
            if binary_right_gets_parens(value, parent_prec) then
                return false
            end
        else
            local inner = value.e1
            if inner.kind ~= "op" or inner.op.prec < value.op.prec then
                return false
            end
            value = inner
        end
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

-- A cast value needs `;`, or the trailing `,` gets read as a return-type separator.
-- The last item's separator is `if_wrapped` so the trailing comma only shows once
-- the list breaks across lines.
local function table_separator(item: parser.Node, is_last: boolean): doc.Doc
    local effective_sep = (item_value_needs_semicolon(item.value) and ";") or ","
    local has_trailing = #(item.trailing_comments or {}) > 0
    local sep = has_trailing and effective_sep or effective_sep .. " "
    if is_last then
        return doc.if_wrapped(sep)
    end
    return doc.text(sep)
end

local function table_item_render_spec(
    ctx: RenderContext, force_wrap: boolean
): ItemRenderSpec
    local function render_item(item: parser.Node): doc.Doc
        return build_table_item_text(ctx, item)
    end
    return delimited_list_doc.ItemRenderSpec.new(
        force_wrap, render_item, table_separator
    )
end

function table_doc.build_table_doc(ctx: RenderContext, items: parser.Node): doc.Doc
    local force_wrap = render_builders.any_items_have_comments(items)
        or items.trailing_comma
        or #(items.dangling_comments or {}) > 0
    local line_doc = render_builders.item_line_doc(force_wrap)

    local items_doc = delimited_list_doc.render_items(
        items, items.dangling_comments or {}, table_item_render_spec(ctx, force_wrap)
    )

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
