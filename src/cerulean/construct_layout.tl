-- How a construct lays out its head, body and closer: whether a control-flow
-- header hangs its expression around the keyword, and the shapes that put an
-- indented body between a header and its `end`. Shared by the statement
-- renderers and the type-body renderers, which frame their bodies identically.
local ast = require("cerulean.ast")
local doc = require("cerulean.doc")
local precedence = require("cerulean.precedence")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")

local type RenderContext = render_context.RenderContext

local construct_layout = {}

-- Whether a control-flow header wraps its expression around the keyword pair
-- (wrap_keyword_around / wrap_keyword_before): only for a bare top-level binary
-- chain. A comment after the opening keyword pins that keyword to its own line,
-- and trivia inside the chain already breaks it, so either routes the header
-- through the inline-trivia path instead.
function construct_layout.should_wrap_condition(
    ctx: RenderContext, node: ast.Node, exp: ast.Node
): boolean
    if #ctx.slots:opener_comments(node, "after_opener") > 0 then
        return false
    end
    return precedence.is_operator_headed(exp)
        and not render_builders.has_chain_internal_trivia(ctx, exp)
end

function construct_layout.wrap_keyword_around(
    keyword: doc.Doc, expression: doc.Doc, closing: doc.Doc
): doc.Doc
    return doc.group(
        doc.concat({keyword, doc.indent_line(expression), doc.line(), closing})
    )
end

function construct_layout.wrap_keyword_before(
    keyword: doc.Doc, expression: doc.Doc
): doc.Doc
    return doc.group(doc.concat({keyword, doc.indent_line(expression)}))
end

-- A soft line here flattens inside a macro statement argument, putting the body
-- back on the call's line and turning the separators between entries into `; `.
function construct_layout.with_indented_body(
    header: doc.Doc, body: doc.Doc, tail: doc.Doc
): doc.Doc
    return doc.concat({header, doc.indent_hardline(body), tail})
end

function construct_layout.block_with_indent(
    header: doc.Doc, body: doc.Doc, footer: doc.Doc
): doc.Doc
    return construct_layout.with_indented_body(
        header, body, doc.concat({doc.line(), footer})
    )
end

function construct_layout.block_with_close(
    header: doc.Doc, body: doc.Doc, close_text: string
): doc.Doc
    return construct_layout.with_indented_body(header, body, doc.close(close_text))
end

return construct_layout
