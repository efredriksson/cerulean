-- AST expression node → doc.Doc. Leaf nodes and simple operators produce flat text;
-- logical chains produce breakable groups at any nesting level; tables delegate to table_doc.
local ast = require("cerulean.ast")
local delimited_list_doc = require("cerulean.delimited_list_doc")
local doc = require("cerulean.doc")
local function_doc = require("cerulean.function_doc")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local table_doc = require("cerulean.table_doc")
local trivia_doc = require("cerulean.trivia_doc")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local expr_doc = {}

-- render_expr is mutually recursive with render_op, so it needs a forward declaration.
local render_expr: function(RenderContext, ast.Node, integer, boolean): doc.Doc

local function render_root_expr(
    ctx: RenderContext, node: ast.Node, same_indent_on_line: boolean
): doc.Doc
    return render_expr(ctx, node, 0, same_indent_on_line)
end

-- A unary operand needs parentheses when it binds looser than the unary parent.
-- Only the strict-less-than rule applies, so equal-precedence unary chains (e.g.
-- "not not x") never need them. Casts expose their own precedence (`as`/`is`);
-- leaves and suffix chains always bind tighter, so they never need parens.
local function operand_needs_unary_parens(
    child: ast.Node, parent_prec: integer
): boolean
    if child.kind == "cast" then
        return render_builders.cast_prec(child) < parent_prec
    end
    if child.kind == "op" and child.op ~= nil then
        return child.op.prec ~= nil and child.op.prec < parent_prec
    end
    return false
end

local function parenthesize_unary_operand(
    rendered: doc.Doc, child: ast.Node, parent_prec: integer
): doc.Doc
    if not operand_needs_unary_parens(child, parent_prec) then
        return rendered
    end
    return doc.group(
        doc.concat({doc.text("("), doc.indent_softline(rendered), doc.softclose(")")})
    )
end

-- Two adjacent `-` tokens form a `--` comment start, so a unary minus applied
-- to another unary minus needs a separating space.
local function unary_separator(op: string, operand: ast.Node): doc.Doc
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
    expression: doc.Doc, comment: ast.Comment | nil
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

local function is_chainable_binary_op(operator: ast.Operator): boolean
    return CHAINABLE_OPS[operator.op] == true
end

local function collect_chain_terms(
    ctx: RenderContext,
    node: ast.Node,
    operator: ast.Operator,
    terms: {ast.Node},
    gap_before_comments: {integer: ast.Comment}
)
    -- Terms are rejoined with the enclosing chain's operator, so only the identical
    -- operator may be flattened into it. `<<` and `>>` share a precedence, and
    -- matching on precedence alone rewrote one into the other.
    if node.kind == "op" and node.op.arity == 2 and node.op.op == operator.op then
        collect_chain_terms(ctx, node.e1, operator, terms, gap_before_comments)
        local lhs_line = node.e1.yend
        local before_op = trivia_doc.partition(
            ctx.slots:op_leading_comments(node), lhs_line
        )
        if before_op then
            gap_before_comments[#terms] = before_op
        end
        collect_chain_terms(ctx, node.e2, operator, terms, gap_before_comments)
        return
    end
    table.insert(terms, node)
end

local function render_paren_in_chain(
    ctx: RenderContext, paren_node: ast.Node, same_indent_on_line: boolean
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
    operator: ast.Operator,
    left: ast.Node,
    right: ast.Node,
    same_indent_on_line: boolean
): doc.Doc
    local operator_prec = operator.prec
    local terms: {ast.Node} = {}
    local gap_before_comments: {integer: ast.Comment} = {}
    collect_chain_terms(ctx, left, operator, terms, gap_before_comments)
    collect_chain_terms(ctx, right, operator, terms, gap_before_comments)

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

local function render_string_literal(node: ast.Node): doc.Doc
    return doc.text(
        render_builders.normalize_string_literal(node.tk, node.is_longstring)
    )
end

-- Flattened, the separator between two statements reads `; ` and a leading comment
-- swallows the rest of the line. One bare statement is safe.
local function block_needs_own_lines(ctx: RenderContext, block: ast.Node): boolean
    return #block ~= 1 or render_builders.any_items_have_comments(ctx, block, false)
end

-- A macro parameter declared `Statement` puts a block where the argument list
-- expects an expression, so one reaches the expression dispatcher.
local function render_statements(ctx: RenderContext, block: ast.Node): doc.Doc
    local rendered = ctx.render_block(block) or doc.text("")
    if block_needs_own_lines(ctx, block) then
        return doc.concat({doc.break_parent(), rendered})
    end
    return rendered
end

-- A macro invocation is a call written `name!(...)`. Teal also accepts the
-- paren-less argument forms a call accepts, and they normalise to parens here the
-- same way `require "m"` does.
local function call_doc_build_call_expr_doc(
    ctx: RenderContext, node: ast.Node, callee: ast.Node, args: ast.Node
): doc.Doc
    local callee_doc = ctx.render_expr(callee, true)
    local bang_doc = node.is_macro_invocation and doc.text("!") or doc.text("")
    local call_args_doc = delimited_list_doc.render_parens(
        ctx, args, args, ctx.render_expr
    )
    return doc.concat({callee_doc, bang_doc, call_args_doc})
end

-- Suffixes (field/method/index/call) bind tighter than any operator, so their
-- base renders with the maximum parent precedence: an operator base parenthesizes
-- itself (`(a + b).c`), every other base renders flush.
local SUFFIX_PREC = 100

-- `base.field` / `base:method`. A comment before the dot/colon anchors to the
-- base's last line; one after it anchors to the separator's own line (`op_y`),
-- so a comment sharing the operator's line hugs it instead of breaking away.
local function render_member(
    ctx: RenderContext, node: ast.Node, same_indent_on_line: boolean
): doc.Doc
    local separator = node.kind == "method" and ":" or "."
    local parts: {doc.Doc} = {
        render_expr(ctx, node.e1, SUFFIX_PREC, same_indent_on_line),
    }
    trivia_doc.emit_transition(
        parts,
        ctx.slots:op_leading_comments(node),
        node.e1.yend,
        doc.text(separator),
        doc.text("")
    )
    trivia_doc.emit_transition(
        parts,
        ctx.slots:op_trailing_comments(node),
        node.op_y,
        doc.text(node.e2.tk),
        doc.text("")
    )
    return doc.concat(parts)
end

-- `base[key]`, spacing the bracket off a long-string key so `[[` never lexes as
-- a long-string opener.
local function render_index(
    ctx: RenderContext, node: ast.Node, same_indent_on_line: boolean
): doc.Doc
    local key = node.e2
    local spacing = render_builders.key_starts_with_long_string(key) and " " or ""
    return doc.concat(
        {
            render_expr(ctx, node.e1, SUFFIX_PREC, same_indent_on_line),
            doc.text("[" .. spacing),
            render_root_expr(ctx, key, false),
            doc.text(spacing .. "]"),
        }
    )
end

-- `expr as Type` / `expr is Type`. The operand renders at the cast's own
-- precedence (`as` binds tighter than every operator, `is` with the relational
-- ops). A comment before the keyword anchors to the operand's last line; one
-- after it anchors to the keyword's own line (`op_y`), so a comment sharing that
-- line hugs the keyword instead of breaking away.
local function render_cast(
    ctx: RenderContext, node: ast.Node, same_indent_on_line: boolean
): doc.Doc
    local keyword = node.is_assertion and "is" or "as"
    local operand_doc = render_expr(
        ctx, node.e1, render_builders.cast_prec(node), same_indent_on_line
    )
    local casttype_doc = type_doc.render(ctx, node.casttype)
    local op_leading = ctx.slots:op_leading_comments(node)
    local op_trailing = ctx.slots:op_trailing_comments(node)

    if #op_leading > 0 or #op_trailing > 0 then
        local parts: {doc.Doc} = {operand_doc}
        trivia_doc.emit_transition(
            parts, op_leading, node.e1.yend, doc.text(keyword), doc.text(" "), true
        )
        trivia_doc.emit_transition(
            parts, op_trailing, node.op_y, casttype_doc, doc.text(" "), true
        )
        return doc.concat(parts)
    end

    -- Only the operator and the cast type go in the group. An operand that
    -- spans lines of its own (a table constructor, a wrapped call) would
    -- otherwise force the break and push a short cast onto its own line.
    local cast_doc = doc.indent(
        doc.concat({doc.line(), doc.text(keyword .. " "), casttype_doc})
    )
    return doc.concat({operand_doc, doc.group(cast_doc)})
end

-- Renders `left op right`, keeping any comment attached to the operator: a
-- comment between the operands is pushed onto its own line instead of dropped.
local function join_op_with_trivia(
    ctx: RenderContext,
    node: ast.Node,
    left_doc: doc.Doc,
    right_doc: doc.Doc,
    plain_separator: doc.Doc
): doc.Doc
    local parts: {doc.Doc} = {left_doc}
    trivia_doc.emit_transition(
        parts,
        ctx.slots:op_leading_comments(node),
        node.e1.yend,
        doc.text(node.op.op),
        plain_separator
    )
    trivia_doc.emit_transition(
        parts,
        ctx.slots:op_trailing_comments(node),
        node.op.y,
        right_doc,
        plain_separator
    )
    return doc.concat(parts)
end

local function render_op(
    ctx: RenderContext,
    node: ast.Node,
    parent_prec: integer,
    same_indent_on_line: boolean
): doc.Doc
    local operator = node.op
    local left = node.e1
    local right = node.e2
    local op = operator.op
    if operator.arity == 1 then
        local op_prec = operator.prec
        local child = parenthesize_unary_operand(
            render_expr(ctx, left, op_prec, same_indent_on_line), left, op_prec
        )
        local plain_sep = unary_separator(op, left)
        local parts: {doc.Doc} = {doc.text(op)}
        trivia_doc.emit_transition(
            parts, ctx.slots:op_trailing_comments(node), operator.y, child, plain_sep
        )
        return parenthesize_if_lower_prec(doc.concat(parts), op_prec, parent_prec)
    else
        local op_prec = operator.prec
        if is_chainable_binary_op(operator) and not ctx.slots:has_op_comments(node) then
            return parenthesize_if_lower_prec(
                render_binary_chain(ctx, operator, left, right, same_indent_on_line),
                op_prec,
                parent_prec
            )
        end
        local joined = join_op_with_trivia(
            ctx,
            node,
            render_expr(ctx, left, op_prec, same_indent_on_line),
            render_expr(ctx, right, op_prec, same_indent_on_line),
            doc.text(" ")
        )
        return parenthesize_if_lower_prec(joined, op_prec, parent_prec)
    end
end

local EXPRESSION_LEAF: {ast.NodeKind: boolean} = {
    ["name"] = true,
    ["..."] = true,
    ["number"] = true,
    ["integer"] = true,
    ["boolean"] = true,
    ["nil"] = true,
}

render_expr = function(
    ctx: RenderContext,
    node: ast.Node,
    parent_prec: integer,
    same_indent_on_line: boolean
): doc.Doc
    if EXPRESSION_LEAF[node.kind] then
        return doc.text(node.tk)
    elseif node.kind == "string" then
        return render_string_literal(node)
    elseif node.kind == "macro_quote" then
        -- The quoted code is one token. Reformatting it would mean parsing a
        -- fragment whose `$` splices are not Teal on their own, so it is passed
        -- through verbatim, as long strings are.
        return doc.text(node.tk)
    elseif node.kind == "paren" then
        return render_paren_in_chain(ctx, node, same_indent_on_line ~= false)
    elseif node.kind == "literal_table" then
        return table_doc.build_table_doc(ctx, node)
    elseif node.kind == "statements" then
        return render_statements(ctx, node)
    elseif node.kind == "function" then
        return function_doc.render_anonymous(ctx, node, doc.text("function"))
    elseif node.kind == "field" or node.kind == "method" then
        return render_member(ctx, node, same_indent_on_line)
    elseif node.kind == "index" then
        return render_index(ctx, node, same_indent_on_line)
    elseif node.kind == "call" then
        return call_doc_build_call_expr_doc(ctx, node, node.e1, node.e2)
    elseif node.kind == "cast" then
        return render_cast(ctx, node, same_indent_on_line)
    elseif node.kind == "op" then
        return render_op(ctx, node, parent_prec, same_indent_on_line)
    end
    error("unsupported expression kind: " .. node.kind)
end

function expr_doc.render(
    ctx: RenderContext, node: ast.Node, same_indent_on_line?: boolean
): doc.Doc
    return render_root_expr(ctx, node, same_indent_on_line)
end

return expr_doc
