-- AST expression node → doc.Doc. Leaf nodes and simple operators produce flat text;
-- logical chains produce breakable groups at any nesting level; tables delegate to table_doc.
local doc = require("formatter.doc")
local function_doc = require("formatter.function_doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local render_context = require("formatter.render_context")
local table_doc = require("formatter.table_doc")
local type_doc = require("formatter.type_doc")

local type RenderContext = render_context.RenderContext

local expr_doc = {}

-- render_expr is mutually recursive with render_op, so it needs a forward declaration.
local render_expr: function(RenderContext, parser.Node, integer): doc.Doc

local function render_root_expr(ctx: RenderContext, node: parser.Node): doc.Doc
    return render_expr(ctx, node, 0)
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

-- Adds parentheses when the parent would otherwise misparse the expression.
local function parenthesize_if_lower_prec(
    rendered: doc.Doc, op_prec: integer, parent_prec: integer
): doc.Doc
    if op_prec < parent_prec then
        return doc.concat({doc.text("("), rendered, doc.text(")")})
    end
    return rendered
end

local function collect_top_level_logical_terms(
    node: parser.Node, operator: parser.Operator, terms: {parser.Node}
)
    if node.kind == "op" and node.op.op == operator.op then
        collect_top_level_logical_terms(node.e1, operator, terms)
        collect_top_level_logical_terms(node.e2, operator, terms)
        return
    end

    table.insert(terms, node)
end

local function is_logical_binary_op(operator: parser.Operator): boolean
    return operator.op == "and" or operator.op == "or"
end

-- Used when a logical sub-expression appears as a term inside a different-operator
-- logical chain. Without this, the sub-chain group would introduce spurious line-break
-- opportunities that corrupt the outer chain's separator decisions.
local function render_logical_expr_flat(
    ctx: RenderContext, node: parser.Node, parent_prec: integer
): doc.Doc
    if node.kind ~= "op" or not is_logical_binary_op(node.op) then
        return render_expr(ctx, node, parent_prec)
    end
    local op_prec = node.op.prec
    local left_doc = render_logical_expr_flat(ctx, node.e1, op_prec)
    local right_doc = render_logical_expr_flat(ctx, node.e2, op_prec)
    return parenthesize_if_lower_prec(
        doc.concat({left_doc, doc.text(" " .. node.op.op .. " "), right_doc}),
        op_prec,
        parent_prec
    )
end

local function render_logical_chain(
    ctx: RenderContext, operator: parser.Operator, left: parser.Node, right: parser.Node
): doc.Doc
    local operator_prec = operator.prec
    local terms: {parser.Node} = {}
    collect_top_level_logical_terms(left, operator, terms)
    collect_top_level_logical_terms(right, operator, terms)

    local parts: {doc.Doc} = {}
    for index, term in ipairs(terms) do
        local term_group_ref = doc.group_ref()
        local term_doc = render_logical_expr_flat(ctx, term, operator_prec)
        table.insert(parts, term_group_ref:group(term_doc))
        if index < #terms then
            table.insert(
                parts,
                term_group_ref:if_break(
                    doc.text(" " .. operator.op .. " "),
                    doc.indent_line(doc.text(operator.op .. " "))
                )
            )
        end
    end
    return doc.group(doc.concat(parts))
end

local function render_string_literal(node: parser.Node): doc.Doc
    if node.is_longstring then
        return doc.text(node.tk)
    end

    local content = node.tk:sub(2, -2)
    if content:find('"', 1, true) then
        return doc.text(node.tk)
    end
    return doc.text('"' .. content .. '"')
end

local function has_any_call_arg_comments(args: parser.Node): boolean
    for _, arg_node in ipairs(args) do
        if #(arg_node.comments or {}) > 0 or arg_node.trailing_comment then
            return true
        end
    end
    return false
end

local function call_doc_build_call_expr_doc(
    ctx: RenderContext, callee: parser.Node, args: parser.Node
): doc.Doc
    local callee_doc = ctx.render_expr(callee)
    local force_wrap = has_any_call_arg_comments(args)
    local line_doc = force_wrap and doc.hardline() or doc.softline()
    local parts: {doc.Doc} = {}
    local line_before = false

    for index, arg_node in ipairs(args) do
        for _, comment in ipairs(arg_node.comments or {}) do
            if line_before then
                table.insert(parts, doc.hardline())
            end
            if comment.blank_line_before then
                table.insert(parts, doc.hardline())
            end
            table.insert(parts, doc.text(comment.text))
            line_before = true
        end
        if line_before then
            table.insert(parts, line_doc)
        end
        if arg_node.blank_line_before then
            table.insert(parts, doc.hardline())
        end
        local arg_doc = ctx.render_expr(arg_node)
        if index < #args then
            local sep = arg_node.trailing_comment and "," or ", "
            arg_doc = doc.concat({arg_doc, doc.text(sep)})
        end
        table.insert(parts, arg_doc)
        table.insert(parts, render_builders.trailing_comment_doc(arg_node))
        line_before = true
    end

    local args_items_doc = doc.concat(parts)
    if not force_wrap then
        args_items_doc = doc.group(args_items_doc)
    end
    local call_args_doc = doc.concat(
        {
            doc.text("("),
            doc.indent_softline(doc.trim_lines(args_items_doc)),
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

local function render_op(
    ctx: RenderContext,
    operator: parser.Operator,
    left: parser.Node,
    right: parser.Node,
    parent_prec: integer
): doc.Doc
    local op = operator.op
    if op == "." or op == ":" then
        return doc.concat(
            {
                render_expr(ctx, left, operator.prec),
                doc.text(op),
                doc.text(right.tk),
            }
        )
    elseif op == "@index" then
        return doc.concat(
            {
                render_expr(ctx, left, operator.prec),
                doc.text("["),
                render_root_expr(ctx, right),
                doc.text("]"),
            }
        )
    elseif op == "@funcall" then
        return call_doc_build_call_expr_doc(ctx, left, right)
    elseif op == "as" or op == "is" then
        return doc.concat(
            {
                render_expr(ctx, left, operator.prec),
                doc.text(" " .. op .. " "),
                type_doc.render(right.casttype),
            }
        )
    elseif operator.arity == 1 then
        local op_prec = operator.prec
        local child = parenthesize_unary_operand(
            render_expr(ctx, left, op_prec), left, op_prec
        )
        local rendered = doc.concat({doc.text(op == "not" and "not " or op), child})
        return parenthesize_if_lower_prec(rendered, op_prec, parent_prec)
    else
        local op_prec = operator.prec
        if is_logical_binary_op(operator) then
            return parenthesize_if_lower_prec(
                render_logical_chain(ctx, operator, left, right), op_prec, parent_prec
            )
        end
        local left_doc = render_expr(ctx, left, op_prec)
        local right_doc = render_expr(ctx, right, op_prec)
        return parenthesize_if_lower_prec(
            doc.concat({left_doc, doc.text(" " .. op .. " "), right_doc}),
            op_prec,
            parent_prec
        )
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
    ctx: RenderContext, node: parser.Node, parent_prec: integer
): doc.Doc
    if EXPRESSION_LEAF[node.kind] then
        return doc.text(node.tk)
    elseif node.kind == "string" then
        return render_string_literal(node)
    elseif node.kind == "paren" then
        return doc.group(
            doc.concat({doc.text("("), render_root_expr(ctx, node.e1), doc.text(")")})
        )
    elseif node.kind == "literal_table" then
        return table_doc.build_table_doc(ctx, node)
    elseif node.kind == "function" then
        return function_doc.render_anonymous(ctx, node, doc.text("function"))
    elseif node.kind == "op" then
        return render_op(ctx, node.op, node.e1, node.e2, parent_prec)
    end
    error("unsupported expression kind: " .. node.kind)
end

function expr_doc.render(ctx: RenderContext, node: parser.Node): doc.Doc
    return render_root_expr(ctx, node)
end

return expr_doc
