-- AST expression node → doc.Doc. Leaf nodes and simple operators produce flat text;
-- logical chains produce breakable groups at any nesting level; tables delegate to table_doc.
local delimited_list_doc = require("cerulean.delimited_list_doc")
local doc = require("cerulean.doc")
local function_doc = require("cerulean.function_doc")
local parser = require("cerulean.parser")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local table_doc = require("cerulean.table_doc")
local trivia_doc = require("cerulean.trivia_doc")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local expr_doc = {}

-- render_expr is mutually recursive with render_op, so it needs a forward declaration.
local render_expr: function(RenderContext, parser.Node, integer, boolean): doc.Doc

local function render_root_expr(
    ctx: RenderContext, node: parser.Node, same_indent_on_line: boolean
): doc.Doc
    return render_expr(ctx, node, 0, same_indent_on_line)
end

-- For unary parents only the strict-less-than rule applies; equal-precedence
-- unary chains (e.g. "not not x") never need parens.
local function parenthesize_unary_operand(
    rendered: doc.Doc, child: parser.Node, parent_prec: integer
): doc.Doc
    if child.kind ~= "op" or child.op == nil then
        return rendered
    end
    local child_prec = child.op.prec
    if child_prec == nil or child_prec >= parent_prec then
        return rendered
    end
    return doc.group(
        doc.concat({doc.text("("), doc.indent_softline(rendered), doc.softclose(")")})
    )
end

-- Two adjacent `-` tokens form a `--` comment start, so a unary minus applied
-- to another unary minus needs a separating space.
local function unary_separator(op: string, operand: parser.Node): doc.Doc
    if op == "not" then
        return doc.text(" ")
    end
    if
        op == "-"
        and operand.kind == "op"
        and operand.op.op == "-"
        and operand.op.arity == 1
    then
        return doc.text(" ")
    end
    return doc.text("")
end

-- Adds parentheses when the parent would otherwise misparse the expression.
local function parenthesize_if_lower_prec(
    rendered: doc.Doc, op_prec: integer, parent_prec: integer
): doc.Doc
    if op_prec < parent_prec then
        return doc.group(
            doc.concat(
                {doc.text("("), doc.indent_softline(rendered), doc.softclose(")")}
            )
        )
    end
    return rendered
end

local function trail_comment_on(
    expression: doc.Doc, comment: parser.Comment | nil
): doc.Doc
    if comment is nil then
        return expression
    end

    return doc.concat({expression, doc.text(" " .. comment.text)})
end

local CHAINABLE_OPS: {string: boolean} = {
    ["or"] = true,
    ["and"] = true,
    [".."] = true,
    ["|"] = true,
    ["~"] = true,
    ["&"] = true,
    ["<<"] = true,
    [">>"] = true,
}

local function is_chainable_binary_op(operator: parser.Operator): boolean
    return CHAINABLE_OPS[operator.op] == true
end

local function collect_chain_terms(
    node: parser.Node,
    operator: parser.Operator,
    terms: {parser.Node},
    gap_before_comments: {integer: parser.Comment}
)
    -- Terms are rejoined with the enclosing chain's operator, so only the identical
    -- operator may be flattened into it. `<<` and `>>` share a precedence, and
    -- matching on precedence alone rewrote one into the other.
    if node.kind == "op" and node.op.arity == 2 and node.op.op == operator.op then
        collect_chain_terms(node.e1, operator, terms, gap_before_comments)
        local lhs_line = node.e1.yend or node.e1.y
        local before_op = trivia_doc.partition(
            parser.inline_trivia(node, "op_leading"), lhs_line
        )
        if before_op then
            gap_before_comments[#terms] = before_op
        end
        collect_chain_terms(node.e2, operator, terms, gap_before_comments)
        return
    end
    table.insert(terms, node)
end

local function render_paren_in_chain(
    ctx: RenderContext, paren_node: parser.Node, same_indent_on_line: boolean
): doc.Doc
    return doc.group(
        doc.concat(
            {
                doc.text("("),
                doc.indent_softline(
                    render_expr(ctx, paren_node.e1, 0, same_indent_on_line)
                ),
                doc.softclose(")"),
            }
        )
    )
end

local function render_binary_chain(
    ctx: RenderContext,
    operator: parser.Operator,
    left: parser.Node,
    right: parser.Node,
    same_indent_on_line: boolean
): doc.Doc
    local operator_prec = operator.prec
    local terms: {parser.Node} = {}
    local gap_before_comments: {integer: parser.Comment} = {}
    collect_chain_terms(left, operator, terms, gap_before_comments)
    collect_chain_terms(right, operator, terms, gap_before_comments)

    local forced_breaks = false
    for _, gap_comment in pairs(gap_before_comments) do
        if gap_comment then
            forced_breaks = true
        end
    end

    local parts: {doc.Doc} = {}
    local first_group_ref = doc.group_ref()
    local first_term_doc = render_expr(
        ctx, terms[1], operator_prec, same_indent_on_line
    )
    first_term_doc = trail_comment_on(first_term_doc, gap_before_comments[1])
    table.insert(parts, first_group_ref:group(first_term_doc))

    local function op_on_line(term_group: doc.Doc, line: doc.Doc): doc.Doc
        local op_and_term_doc = doc.concat(
            {line, doc.text(operator.op .. " "), term_group}
        )

        if same_indent_on_line then
            return op_and_term_doc
        else
            return doc.indent(op_and_term_doc)
        end
    end

    local prev_group_ref = first_group_ref
    for index = 2, #terms do
        local term = terms[index]
        local term_group_ref = doc.group_ref()
        if forced_breaks then
            local term_doc = render_expr(ctx, term, operator_prec, false)
            term_doc = trail_comment_on(term_doc, gap_before_comments[index])
            local term_group = term_group_ref:group(term_doc)
            table.insert(parts, op_on_line(term_group, doc.hardline()))
        elseif term.kind == "paren" then
            local term_doc = render_paren_in_chain(ctx, term, true)
            local term_group = term_group_ref:group(term_doc)
            table.insert(parts, op_on_line(term_group, doc.line()))
        else
            local term_doc = render_expr(ctx, term, operator_prec, false)
            local term_group = term_group_ref:group(term_doc)
            local op_and_term = doc.concat(
                {doc.text(" " .. operator.op .. " "), term_group}
            )
            table.insert(
                parts,
                prev_group_ref:if_break(op_and_term, op_on_line(term_group, doc.line()))
            )
        end
        prev_group_ref = term_group_ref
    end
    return doc.group(doc.concat(parts))
end

local function render_string_literal(node: parser.Node): doc.Doc
    return doc.text(
        render_builders.normalize_string_literal(node.tk, node.is_longstring)
    )
end

local function call_doc_build_call_expr_doc(
    ctx: RenderContext, callee: parser.Node, args: parser.Node
): doc.Doc
    local callee_doc = ctx.render_expr(callee, true)
    local call_args_doc = delimited_list_doc.render_parens(args, args, ctx.render_expr)
    local args_tc = render_builders.trailing_comment_doc(args)
    return doc.concat({callee_doc, call_args_doc, args_tc})
end

local function op_has_any_trivia(node: parser.Node): boolean
    return #parser.inline_trivia(node, "op_leading") > 0
        or #parser.inline_trivia(node, "op_trailing") > 0
end

-- Renders `left op right`, keeping any comment attached to the operator: a
-- comment between the operands is pushed onto its own line instead of dropped.
local function join_op_with_trivia(
    node: parser.Node, left_doc: doc.Doc, right_doc: doc.Doc, plain_separator: doc.Doc
): doc.Doc
    local parts: {doc.Doc} = {left_doc}
    trivia_doc.emit_transition(
        parts,
        parser.inline_trivia(node, "op_leading"),
        node.e1.yend or node.e1.y,
        doc.text(node.op.op),
        plain_separator
    )
    trivia_doc.emit_transition(
        parts,
        parser.inline_trivia(node, "op_trailing"),
        node.op.y,
        right_doc,
        plain_separator
    )
    return doc.concat(parts)
end

local function render_op(
    ctx: RenderContext,
    node: parser.Node,
    parent_prec: integer,
    same_indent_on_line: boolean
): doc.Doc
    local operator = node.op
    local left = node.e1
    local right = node.e2
    local op = operator.op
    if op == "." or op == ":" then
        return join_op_with_trivia(
            node,
            render_expr(ctx, left, operator.prec, same_indent_on_line),
            doc.text(right.tk),
            doc.text("")
        )
    elseif op == "@index" then
        local spacing = render_builders.key_starts_with_long_string(right) and " " or ""
        return doc.concat(
            {
                render_expr(ctx, left, operator.prec, same_indent_on_line),
                doc.text("[" .. spacing),
                render_root_expr(ctx, right, false),
                doc.text(spacing .. "]"),
            }
        )
    elseif op == "@funcall" then
        return call_doc_build_call_expr_doc(ctx, left, right)
    elseif op == "as" or op == "is" then
        local left_doc = render_expr(ctx, left, operator.prec, same_indent_on_line)
        local casttype_doc = type_doc.render(right.casttype)
        if op_has_any_trivia(node) then
            return join_op_with_trivia(node, left_doc, casttype_doc, doc.text(" "))
        end
        -- Only the operator and the cast type go in the group. An operand that
        -- spans lines of its own (a table constructor, a wrapped call) would
        -- otherwise force the break and push a short cast onto its own line.
        local cast_doc = doc.indent(
            doc.concat({doc.line(), doc.text(op .. " "), casttype_doc})
        )
        return doc.concat({left_doc, doc.group(cast_doc)})
    elseif operator.arity == 1 then
        local op_prec = operator.prec
        local child = parenthesize_unary_operand(
            render_expr(ctx, left, op_prec, same_indent_on_line), left, op_prec
        )
        local plain_sep = unary_separator(op, left)
        local parts: {doc.Doc} = {doc.text(op)}
        trivia_doc.emit_transition(
            parts,
            parser.inline_trivia(node, "op_trailing"),
            operator.y,
            child,
            plain_sep
        )
        return parenthesize_if_lower_prec(doc.concat(parts), op_prec, parent_prec)
    else
        local op_prec = operator.prec
        if is_chainable_binary_op(operator) and not op_has_any_trivia(node) then
            return parenthesize_if_lower_prec(
                render_binary_chain(ctx, operator, left, right, same_indent_on_line),
                op_prec,
                parent_prec
            )
        end
        local joined = join_op_with_trivia(
            node,
            render_expr(ctx, left, op_prec, same_indent_on_line),
            render_expr(ctx, right, op_prec, same_indent_on_line),
            doc.text(" ")
        )
        return parenthesize_if_lower_prec(joined, op_prec, parent_prec)
    end
end

local EXPRESSION_LEAF: {parser.NodeKind: boolean} = {
    ["variable"] = true,
    ["identifier"] = true,
    ["..."] = true,
    ["number"] = true,
    ["integer"] = true,
    ["boolean"] = true,
    ["nil"] = true,
}

render_expr = function(
    ctx: RenderContext,
    node: parser.Node,
    parent_prec: integer,
    same_indent_on_line: boolean
): doc.Doc
    if EXPRESSION_LEAF[node.kind] then
        return doc.text(node.tk)
    elseif node.kind == "string" then
        return render_string_literal(node)
    elseif node.kind == "paren" then
        return render_paren_in_chain(ctx, node, same_indent_on_line ~= false)
    elseif node.kind == "literal_table" then
        return table_doc.build_table_doc(ctx, node)
    elseif node.kind == "function" then
        return function_doc.render_anonymous(ctx, node, doc.text("function"))
    elseif node.kind == "op" then
        return render_op(ctx, node, parent_prec, same_indent_on_line)
    end
    error("unsupported expression kind: " .. node.kind)
end

function expr_doc.render(
    ctx: RenderContext, node: parser.Node, same_indent_on_line?: boolean
): doc.Doc
    return render_root_expr(ctx, node, same_indent_on_line)
end

return expr_doc
