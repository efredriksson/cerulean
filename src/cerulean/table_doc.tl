-- Table constructor → doc.Doc (build_table_doc).
local ast = require("cerulean.ast")
local delimited_list_doc = require("cerulean.delimited_list_doc")
local doc = require("cerulean.doc")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext
local type ItemRenderSpec = delimited_list_doc.ItemRenderSpec

local table_doc = {}

local function binary_right_gets_parens(child: ast.Node, parent_prec: integer): boolean
    if child.kind ~= "op" then
        return false
    end
    return child.op.prec < parent_prec
end

-- The binding precedence of a unary operand for the rightmost-spine walk: an
-- operator's own, a cast's, or 0 for anything that ends the spine.
local function unary_operand_prec(node: ast.Node): integer
    if node.kind == "cast" then
        return render_builders.cast_prec(node)
    end
    if node.kind == "op" then
        return node.op.prec
    end
    return 0
end

-- `x as function(): T, next` re-parses as `x as function(): (T, next)`: the table
-- separator `,` is greedily consumed as a return-type component. Use `;` instead.
-- Walks the rightmost operand spine to find such a cast, stopping when the
-- renderer would already wrap the subtree in parens, making the `,` safe.
local function item_value_needs_semicolon(value: ast.Node): boolean
    while true do
        if value.kind == "cast" then
            return type_doc.cast_absorbs_trailing_comma(value.casttype)
        end
        if value.kind ~= "op" then
            return false
        end
        if value.op.arity == 2 then
            local parent_prec = value.op.prec
            value = value.e2
            if binary_right_gets_parens(value, parent_prec) then
                return false
            end
        else
            local inner = value.e1
            if unary_operand_prec(inner) < value.op.prec then
                return false
            end
            value = inner
        end
    end
end

local function build_table_item_text(ctx: RenderContext, item: ast.Node): doc.Doc
    if item.key_parsed == "implicit" then
        return ctx.render_expr(item.value)
    elseif item.key_parsed == "short" then
        local key_text = item.key.conststr or item.key.tk
        if item.itemtype ~= nil then
            return doc.concat(
                {
                    doc.text(key_text .. ": "),
                    type_doc.render(ctx, item.itemtype),
                    doc.text(" = "),
                    ctx.render_expr(item.value),
                }
            )
        end
        return render_builders.with_leading_inline_trivia(
            ctx.slots:opener_comments(item, "after_opener"),
            doc.text(key_text .. " = "),
            ctx.render_expr(item.value)
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
local function table_separator(
    ctx: RenderContext, item: ast.Node, is_last: boolean
): doc.Doc
    local effective_sep = (item_value_needs_semicolon(item.value) and ";") or ","
    local has_trailing = #ctx.slots:trailing_comments(item) > 0
    local sep = has_trailing and effective_sep or effective_sep .. " "
    if is_last then
        return doc.if_wrapped(sep)
    end
    return doc.text(sep)
end

local function table_item_render_spec(
    ctx: RenderContext, force_wrap: boolean
): ItemRenderSpec
    local function render_item(item: ast.Node): doc.Doc
        return build_table_item_text(ctx, item)
    end
    local function make_separator(item: ast.Node, is_last: boolean): doc.Doc
        return table_separator(ctx, item, is_last)
    end
    return delimited_list_doc.ItemRenderSpec.new(
        force_wrap, render_item, make_separator, true
    )
end

function table_doc.build_table_doc(ctx: RenderContext, items: ast.Node): doc.Doc
    local dangling = ctx.slots:container_dangling_comments(items, #items == 0)
    local force_wrap = render_builders.any_items_have_comments(ctx, items, true)
        or items.trailing_comma
        or #dangling > 0
    local line_doc = render_builders.item_line_doc(force_wrap)

    local items_doc = delimited_list_doc.render_items(
        ctx, items, dangling, table_item_render_spec(ctx, force_wrap)
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
