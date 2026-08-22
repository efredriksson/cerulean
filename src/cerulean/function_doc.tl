-- Render any function, regular and anonymous
-- header prefix ("local function foo" vs "function").
local ast = require("cerulean.ast")
local doc = require("cerulean.doc")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local function_doc = {}

function function_doc.render(
    ctx: RenderContext, node: ast.Node, header_prefix: doc.Doc
): doc.Doc
    assert(node.args ~= nil and node.body ~= nil, "bad function node")

    -- measure_flat: a return annotation's break opportunities must not absorb a
    -- too-wide parameter list; the params break first, the annotation only after.
    local sig_doc = doc.group(
        doc.concat(
            {
                type_doc.render_parameter_list(ctx, node.args),
                doc.measure_flat(type_doc.render_return(ctx, node.rets)),
            }
        )
    )
    local header = doc.concat(
        {
            doc.group(doc.concat({header_prefix, sig_doc})),
            render_builders.head_trivia_doc(ctx.slots:opener_comments(node, "head")),
        }
    )
    local body_doc = ctx.render_block(node.body)
    assert(body_doc ~= nil, "bad body not caught early")
    return doc.concat(
        {
            header,
            doc.indent_line(doc.trim_lines(body_doc)),
            doc.close("end"),
        }
    )
end

function function_doc.render_anonymous(
    ctx: RenderContext, node: ast.Node, header_prefix: doc.Doc
): doc.Doc
    if node.typeargs ~= nil and #node.typeargs > 0 then
        header_prefix = doc.concat(
            {header_prefix, type_doc.render_typeargs(ctx, node.typeargs)}
        )
    end

    local rendered = function_doc.render(ctx, node, header_prefix)
    -- comment_doc only breaks the group for a comment at a statement boundary (a body
    -- statement's leading/trailing). A header or argument comment, or any block
    -- comment, does not self-break and would fold the body onto the header line. Force
    -- the group open whenever the function carries any comment so those expand too.
    if
        render_builders.block_has_any_comments(ctx, node.body)
        or #ctx.slots:opener_comments(node, "head") > 0
        or render_builders.any_items_have_comments(ctx, node.args, false)
    then
        return doc.concat({rendered, doc.break_parent()})
    end
    return doc.group(rendered)
end

return function_doc
