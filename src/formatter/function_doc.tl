-- Render any function, regular and anonymous
-- header prefix ("local function foo" vs "function").
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_context = require("formatter.render_context")
local signature_doc = require("formatter.signature_doc")
local type_doc = require("formatter.type_doc")

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
    local header = doc.group(doc.concat({header_prefix, sig_doc}))
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
    ctx: RenderContext, node: parser.Node, header_prefix: doc.Doc
): doc.Doc
    return doc.group(function_doc.render(ctx, node, header_prefix))
end

return function_doc
