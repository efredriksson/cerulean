-- AST expression node → doc.Doc. Leaf nodes and simple operators produce flat text;
-- logical chains produce breakable groups at any nesting level; tables delegate to table_doc.
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
    return doc.concat({doc.text("("), rendered, doc.text(")")})
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
        return doc.concat({doc.text("("), rendered, doc.text(")")})
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
    if node.kind == "op" and node.op.prec == operator.prec then
        collect_chain_terms(node.e1, operator, terms, gap_before_comments)
        local lhs_line = node.e1.yend or node.e1.y
        local before_op = trivia_doc.partition(node.op_leading_trivia, lhs_line)
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
    local force_wrap = render_builders.any_items_have_comments(args)
        or #(args.leading_inline_trivia or {}) > 0
    local parts: {doc.Doc} = {}
    local line_before = false

    for index, arg_node in ipairs(args) do
        line_before = render_builders.append_comment_docs(
            parts, arg_node.leading_comments or {}, line_before
        )
        table.insert(
            parts, render_builders.append_lines_pre_node(arg_node, line_before)
        )
        local arg_parts: {doc.Doc} = {ctx.render_expr(arg_node)}
        trivia_doc.append_inline(arg_parts, arg_node.trailing_trivia)
        if index < #args then
            local sep = arg_node.trailing_comment and "," or ", "
            table.insert(arg_parts, doc.text(sep))
        end
        table.insert(parts, doc.concat(arg_parts))
        table.insert(parts, render_builders.trailing_comment_doc(arg_node))
        line_before = true
    end

    local args_items_doc = doc.concat(parts)
    if not force_wrap then
        args_items_doc = doc.group(args_items_doc)
    end

    local function build_args_doc(): doc.Doc
        local arg_items_trimed = doc.trim_lines(args_items_doc)
        if #(args.leading_inline_trivia or {}) > 0 then
            local prefix_parts: {doc.Doc} = {}
            trivia_doc.append_inline_joined(prefix_parts, args.leading_inline_trivia)
            table.insert(prefix_parts, doc.indent_hardline(arg_items_trimed))
            return doc.concat(prefix_parts)
        else
            return doc.concat(
                {
                    doc.indent_softline(arg_items_trimed),
                }
            )
        end
    end

    local call_args_doc = doc.concat(
        {
            doc.text("("),
            build_args_doc(),
            doc.softclose(")"),
        }
    )
    if force_wrap then
        call_args_doc = doc.concat({doc.break_parent(), call_args_doc})
    else
        call_args_doc = doc.group(call_args_doc)
    end

    local args_tc = render_builders.trailing_comment_doc(args)
    return doc.concat({callee_doc, call_args_doc, args_tc})
end

local function op_has_any_trivia(node: parser.Node): boolean
    return (node.op_leading_trivia ~= nil and #node.op_leading_trivia > 0)
        or (node.op_trailing_trivia ~= nil and #node.op_trailing_trivia > 0)
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
        return doc.concat(
            {
                render_expr(ctx, left, operator.prec, same_indent_on_line),
                doc.text(op),
                doc.text(right.tk),
            }
        )
    elseif op == "@index" then
        local function get_bracket_spacing(): string
            -- A long-string key like [[k]] must be spaced away from the index `[`
            -- to prevent `[[[k]]]` which in teal is a long string
            if right.is_longstring then
                return " "
            else
                return ""
            end
        end
        return doc.concat(
            {
                render_expr(ctx, left, operator.prec, same_indent_on_line),
                doc.text("[" .. get_bracket_spacing()),
                render_root_expr(ctx, right, same_indent_on_line),
                doc.text(get_bracket_spacing() .. "]"),
            }
        )
    elseif op == "@funcall" then
        return call_doc_build_call_expr_doc(ctx, left, right)
    elseif op == "as" or op == "is" then
        return doc.concat(
            {
                render_expr(ctx, left, operator.prec, same_indent_on_line),
                doc.text(" " .. op .. " "),
                type_doc.render(right.casttype),
            }
        )
    elseif operator.arity == 1 then
        local op_prec = operator.prec
        local child = parenthesize_unary_operand(
            render_expr(ctx, left, op_prec, same_indent_on_line), left, op_prec
        )
        local plain_sep = unary_separator(op, left)
        local parts: {doc.Doc} = {doc.text(op)}
        trivia_doc.emit_transition(
            parts, node.op_trailing_trivia, operator.y, child, plain_sep
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
        local lhs_line = left.yend or left.y
        local left_doc = render_expr(ctx, left, op_prec, same_indent_on_line)
        local right_doc = render_expr(ctx, right, op_prec, same_indent_on_line)
        local parts: {doc.Doc} = {left_doc}
        trivia_doc.emit_transition(
            parts, node.op_leading_trivia, lhs_line, doc.text(op), doc.text(" ")
        )
        trivia_doc.emit_transition(
            parts, node.op_trailing_trivia, operator.y, right_doc, doc.text(" ")
        )
        return parenthesize_if_lower_prec(doc.concat(parts), op_prec, parent_prec)
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
        return render_paren_in_chain(ctx, node, true)
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
