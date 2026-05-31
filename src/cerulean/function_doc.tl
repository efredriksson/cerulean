-- Render any function, regular and anonymous
-- header prefix ("local function foo" vs "function").
local doc = require("cerulean.doc")
local parser = require("cerulean.parser")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local signature_doc = require("cerulean.signature_doc")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local function_doc = {}

function function_doc.render(
    ctx: RenderContext, node: parser.Node, header_prefix: doc.Doc
): doc.Doc
    assert(node.args ~= nil and node.body ~= nil, "bad function node")

    local sig_doc = doc.group(
        doc.concat(
            {
                signature_doc.render_signature_doc(node.args),
                type_doc.render_return(node.rets),
            }
        )
    )
    local header = doc.concat(
        {
            doc.group(doc.concat({header_prefix, sig_doc})),
            render_builders.head_trivia_doc(node),
        }
    )
    local body_doc = ctx.render_block(node.body)
    assert(body_doc ~= nil, "bad body not caught early")
    local func_doc = doc.concat(
        {
            header,
            doc.indent_line(doc.trim_lines(body_doc)),
            doc.close("end"),
        }
    )
    if #parser.inline_trivia(node, "head") > 0 then
        func_doc = doc.concat({func_doc, doc.break_parent()})
    end
    return func_doc
end

function function_doc.render_anonymous(
    ctx: RenderContext, node: parser.Node, header_prefix: doc.Doc
): doc.Doc
    if node.typeargs ~= nil and #node.typeargs > 0 then
        header_prefix = doc.concat(
            {header_prefix, type_doc.render_typeargs(node.typeargs)}
        )
    end

    local rendered = function_doc.render(ctx, node, header_prefix)
    if
        render_builders.block_has_any_comments(node.body)
        or #parser.inline_trivia(node, "head") > 0
    then
        return doc.concat({rendered, doc.break_parent()})
    end
    return doc.group(rendered)
end

return function_doc
