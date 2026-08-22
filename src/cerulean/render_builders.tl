local ast = require("cerulean.ast")
local doc = require("cerulean.doc")
local render_context = require("cerulean.render_context")
local trivia_doc = require("cerulean.trivia_doc")

local type RenderContext = render_context.RenderContext

local render_builders = {}

function render_builders.normalize_string_literal(
    tk: string, is_longstring: boolean
): string
    if is_longstring then
        return tk
    end
    local content = tk:sub(2, -2)
    if content:find('"', 1, true) then
        return tk
    end
    return '"' .. content .. '"'
end

function render_builders.build_comma_line_item_docs(item_docs: {doc.Doc}): doc.Doc
    local parts: {doc.Doc} = {}

    for index, item_doc in ipairs(item_docs) do
        table.insert(parts, item_doc)
        if index < #item_docs then
            table.insert(parts, doc.text(","))
            table.insert(parts, doc.line())
        end
    end

    return doc.concat(parts)
end

-- Every comma gives at once: the list is one line or one item per line, never a
-- ragged fill. Shared by delimited sequences and `=` value lists.
function render_builders.build_grouped_comma_items_doc(item_docs: {doc.Doc}): doc.Doc
    return doc.group(render_builders.build_comma_line_item_docs(item_docs))
end

function render_builders.build_separated_docs(
    item_docs: {doc.Doc}, separator: string
): doc.Doc
    local parts: {doc.Doc} = {}
    for index, item_doc in ipairs(item_docs) do
        table.insert(parts, item_doc)
        if index < #item_docs then
            table.insert(parts, doc.text(separator))
        end
    end
    return doc.concat(parts)
end

function render_builders.build_comma_separated_docs(item_docs: {doc.Doc}): doc.Doc
    return render_builders.build_separated_docs(item_docs, ", ")
end

local function mapped_exp_docs(ctx: RenderContext, nodes: {ast.Node}): {doc.Doc}
    local item_docs: {doc.Doc} = {}
    for _, node in ipairs(nodes) do
        table.insert(item_docs, ctx.render_expr(node))
    end
    return item_docs
end

function render_builders.build_mapped_comma_separated_docs(
    ctx: RenderContext, nodes: {ast.Node}
): doc.Doc
    return render_builders.build_comma_separated_docs(mapped_exp_docs(ctx, nodes))
end

function render_builders.trailing_comment_doc(comments: {ast.Comment}): doc.Doc
    local parts: {doc.Doc} = {}
    for _, comment in ipairs(comments) do
        table.insert(
            parts, doc.concat({doc.text(" "), trivia_doc.comment_doc(comment)})
        )
    end
    return doc.concat(parts)
end

function render_builders.head_trivia_doc(head: {ast.Comment}): doc.Doc
    if #head == 0 then
        return doc.text("")
    end
    local parts: {doc.Doc} = {}
    trivia_doc.append_inline(parts, head)
    return doc.concat(parts)
end

-- `exclude_last_trailing` skips the trailing-comment check on the final item: for
-- a sugar call (`t{}`, `t"s"`) the sole argument has no closing token of its own,
-- so its last token is also the call's, and the comment after it is the call's
-- own trailing, read and rendered outside this list (see render_parens).
function render_builders.any_items_have_comments(
    ctx: RenderContext,
    items: ast.Node,
    absorb_first_opener: boolean,
    exclude_last_trailing?: boolean
): boolean
    for index, item in ipairs(items) do
        local leading = ctx.slots:item_leading_comments(
            item, items[index - 1], index == 1 and absorb_first_opener
        )
        local checks_trailing = not (exclude_last_trailing and index == #items)
        if
            #leading > 0 or (checks_trailing and #ctx.slots:trailing_comments(item) > 0)
        then
            return true
        end
    end
    return false
end

-- A threaded comment pins its item to a line of its own, so the commas stop being
-- free break points and the list has to render through the comment path.
function render_builders.exp_list_can_break(
    ctx: RenderContext, exps: {ast.Node}
): boolean
    return #exps > 1 and not render_builders.any_items_have_comments(ctx, exps, false)
end

-- Join pre-rendered list items with ", ", but when a non-last item carries a
-- trailing comment (a line comment after it or its separator) emit the comma, the
-- comment, and a hardline so the next item starts on its own line. Callers that can
-- render their items through ctx.render_expr use build_exp_list_doc; this one takes
-- pre-rendered docs for lists whose items carry syntax render_expr does not (a
-- variable list's `<const>` attributes), so the caller owns item rendering and this
-- owns the separators + per-item trailing.
function render_builders.build_comma_separated_with_trailing(
    ctx: RenderContext, items: {ast.Node}, item_docs: {doc.Doc}
): doc.Doc
    local parts: {doc.Doc} = {}
    local force_next_indent = false
    for index, item_doc in ipairs(item_docs) do
        local rendered = item_doc
        if force_next_indent then
            rendered = doc.indent_hardline(rendered)
            force_next_indent = false
        end
        if index < #item_docs then
            local trailing = ctx.slots:trailing_comments(items[index])
            if #trailing > 0 then
                local trailing_parts: {doc.Doc} = {rendered, doc.text(",")}
                for _, comment in ipairs(trailing) do
                    table.insert(trailing_parts, doc.text(" " .. comment.text))
                end
                rendered = doc.concat(trailing_parts)
                force_next_indent = true
            else
                rendered = doc.concat({rendered, doc.text(", ")})
            end
        end
        table.insert(parts, rendered)
    end
    return doc.concat(parts)
end

function render_builders.build_exp_list_doc(
    ctx: RenderContext, exps: {ast.Node}
): doc.Doc
    if not render_builders.any_items_have_comments(ctx, exps, false) then
        return render_builders.build_grouped_comma_items_doc(mapped_exp_docs(ctx, exps))
    end
    local item_docs: {doc.Doc} = {}
    for _, exp in ipairs(exps) do
        table.insert(item_docs, ctx.render_expr(exp))
    end
    return render_builders.build_comma_separated_with_trailing(ctx, exps, item_docs)
end

-- The first value stays on the `return` line: unlike an `=` list there is no
-- operator to its left to give first, so only the continuations indent.
function render_builders.build_return_exp_list_doc(
    ctx: RenderContext, exps: {ast.Node}
): doc.Doc
    if not render_builders.exp_list_can_break(ctx, exps) then
        return render_builders.build_exp_list_doc(ctx, exps)
    end
    local item_docs = mapped_exp_docs(ctx, exps)
    -- Outside the indent, so only the continuations shift right.
    local first_doc = table.remove(item_docs, 1)
    local continuations = doc.concat(
        {
            doc.text(","),
            doc.line(),
            render_builders.build_comma_line_item_docs(item_docs),
        }
    )
    return doc.concat({first_doc, doc.group(doc.indent(continuations))})
end

function render_builders.block_has_any_comments(
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

function render_builders.item_line_doc(should_force_wrap: boolean): doc.Doc
    if should_force_wrap then
        return doc.hardline()
    else
        return doc.softline()
    end
end

function render_builders.append_lines_pre_node(
    node: ast.Node | ast.FieldEntry,
    line_before: boolean,
    line_from_before?: doc.Doc,
    suppress_blank?: boolean
): doc.Doc
    local parts: {doc.Doc} = {}
    if line_before then
        table.insert(parts, line_from_before or doc.softline())
    end
    if node.blank_line_before and not suppress_blank then
        -- enclosing group MUST break, for example anon function.
        table.insert(parts, doc.concat({doc.hardline(), doc.break_parent()}))
    end

    return doc.concat(parts)
end

-- The binding precedence a cast exposes to a parent expression: `as` binds
-- tighter than every operator, while `is` sits with the relational ops. Held
-- here rather than on the node so the parser need not carry operator metadata
-- for casts.
local AS_PREC = 50
local IS_PREC = 3

function render_builders.cast_prec(node: ast.Node): integer
    if node.is_assertion then
        return IS_PREC
    end
    return AS_PREC
end

-- A control-flow head wraps its expression with a hanging indent for a binary
-- op or a cast: a long condition ending in either breaks around the keyword
-- rather than overflowing the line.
function render_builders.is_top_level_binary_op(node: ast.Node): boolean
    if node.kind == "cast" then
        return true
    end
    if node.kind ~= "op" or node.op == nil then
        return false
    end
    return node.op.arity == 2
end

-- Operators, casts, and the suffix chain (field/method/index/call) are the nodes
-- whose subtree can hold op trivia worth descending into.
local CHAIN_NODE_KINDS: {ast.NodeKind: boolean} = {
    ["op"] = true,
    ["cast"] = true,
    ["field"] = true,
    ["method"] = true,
    ["index"] = true,
    ["call"] = true,
}

function render_builders.has_chain_internal_trivia(
    ctx: RenderContext, node: ast.Node
): boolean
    if not CHAIN_NODE_KINDS[node.kind] then
        return false
    end
    if #ctx.slots:op_leading_comments(node) > 0 then
        return true
    end
    if #ctx.slots:op_trailing_comments(node) > 0 then
        return true
    end
    if node.e1 ~= nil and render_builders.has_chain_internal_trivia(ctx, node.e1) then
        return true
    end
    if node.e2 ~= nil and render_builders.has_chain_internal_trivia(ctx, node.e2) then
        return true
    end
    return false
end

function render_builders.wrap_keyword_around(
    keyword: doc.Doc, expression: doc.Doc, closing: doc.Doc
): doc.Doc
    return doc.group(
        doc.concat({keyword, doc.indent_line(expression), doc.line(), closing})
    )
end

function render_builders.wrap_keyword_before(
    keyword: doc.Doc, expression: doc.Doc
): doc.Doc
    return doc.group(doc.concat({keyword, doc.indent_line(expression)}))
end

function render_builders.with_leading_inline_trivia(
    after_opener: {ast.Comment}, prefix: doc.Doc, content: doc.Doc
): doc.Doc
    if #after_opener == 0 then
        return doc.concat({prefix, content})
    end
    local parts: {doc.Doc} = {prefix}
    trivia_doc.append_inline_joined(parts, after_opener)
    table.insert(parts, doc.indent_hardline(content))
    return doc.concat(parts)
end

function render_builders.append_comment_docs(
    parts: {doc.Doc}, comments: {ast.Comment}, line_before: boolean
): boolean
    for _, comment in ipairs(comments) do
        if line_before then
            table.insert(parts, doc.hardline())
        end
        if comment.blank_line_before then
            table.insert(parts, doc.hardline())
        end
        table.insert(parts, trivia_doc.comment_doc(comment))
        line_before = true
    end
    return line_before
end

function render_builders.key_starts_with_long_string(node: ast.Node): boolean
    -- When the key expression's leftmost token is a long string, the subscript `[`
    -- must be spaced away to prevent `[[[k]]` from being lexed as a long string.
    if node.is_longstring then
        return true
    end
    local descends_left = node.kind == "field"
        or node.kind == "method"
        or node.kind == "index"
        or node.kind == "call"
        or node.kind == "cast"
        or (node.kind == "op" and node.op.arity == 2)
    return descends_left and render_builders.key_starts_with_long_string(node.e1)
end

return render_builders
