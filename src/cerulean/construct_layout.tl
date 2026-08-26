-- How a construct lays out its head, body and closer: whether a control-flow
-- header hangs its expression around the keyword, and the shapes that put an
-- indented body between a header and its `end`. Shared by the statement
-- renderers and the type-body renderers, which frame their bodies identically.
local ast = require("cerulean.ast")
local doc = require("cerulean.doc")
local precedence = require("cerulean.precedence")
local render_context = require("cerulean.render_context")

local type RenderContext = render_context.RenderContext

local construct_layout = {}

-- `exclude_last_trailing` skips the trailing-comment check on the final item: for
-- a sugar call (`t{}`, `t"s"`) the sole argument has no closing token of its own,
-- so its last token is also the call's, and the comment after it is the call's
-- own trailing, read and rendered outside this list (see render_parens).
function construct_layout.any_items_have_comments(
    ctx: RenderContext,
    items: ast.Node,
    absorb_first_opener: boolean,
    exclude_last_trailing?: boolean
): boolean
    for index, item in ipairs(items) do
        local leading_extent = ctx.slots:leading_extent(
            item, items[index - 1], index == 1 and absorb_first_opener
        )
        local checks_trailing = not (exclude_last_trailing and index == #items)
        if
            leading_extent > 0
            or (checks_trailing and ctx.slots:trailing_extent(item) > 0)
        then
            return true
        end
    end
    return false
end

function construct_layout.block_has_any_comments(
    ctx: RenderContext, block: ast.Node
): boolean
    for _, stmt in ipairs(block) do
        if
            #ctx.slots:leading_comments(stmt) > 0
            or #ctx.slots:statement_trailing_comments(stmt) > 0
        then
            return true
        end
    end
    return #ctx.slots:dangling_comments(block) > 0
end

-- The binding precedence a cast exposes to a parent expression: `as` binds
-- tighter than every operator, while `is` sits with the relational ops. Held
-- here rather than on the node so the parser need not carry operator metadata
-- for casts.
-- Operator trivia anywhere on the operand spine belongs to the enclosing chain,
-- including under a node that carries no operator token itself, such as a paren.
function construct_layout.has_chain_internal_trivia(
    ctx: RenderContext, node: ast.Node
): boolean
    if ctx.slots:has_op_comments(node) then
        return true
    end
    if node.e1 ~= nil and construct_layout.has_chain_internal_trivia(ctx, node.e1) then
        return true
    end
    if node.e2 ~= nil and construct_layout.has_chain_internal_trivia(ctx, node.e2) then
        return true
    end
    return false
end

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
        and not construct_layout.has_chain_internal_trivia(ctx, exp)
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
