-- AST expression node → compact single-line string. Now never produces wrapping or line breaks.
-- Use call_doc.build_call_expr_doc / table_doc.build_table_doc when wrapping is needed.
local call_doc = require("formatter.call_doc")
local doc = require("formatter.doc")
local function_doc = require("formatter.function_doc")
local parser = require("formatter.parser")
local render_context = require("formatter.render_context")
local table_doc = require("formatter.table_doc")
local type_doc = require("formatter.type_doc")

local type RenderContext = render_context.RenderContext

local expr_doc = {}

local PRECEDENCE: {string: integer} = {
    ["or"] = 1,
    ["and"] = 2,
    ["is"] = 3,
    ["<"] = 3,
    [">"] = 3,
    ["<="] = 3,
    [">="] = 3,
    ["~="] = 3,
    ["=="] = 3,
    ["|"] = 4,
    ["~"] = 5,
    ["&"] = 6,
    ["<<"] = 7,
    [">>"] = 7,
    [".."] = 8,
    ["+"] = 9,
    ["-"] = 9,
    ["*"] = 10,
    ["/"] = 10,
    ["//"] = 10,
    ["%"] = 10,
    ["not"] = 11,
    ["#"] = 11,
    ["unary-"] = 11,
    ["unary~"] = 11,
    ["^"] = 12,
    ["as"] = 50,
    ["@funcall"] = 100,
    ["@index"] = 100,
    ["."] = 100,
    [":"] = 100,
}

local RIGHT_ASSOC: {string: boolean} = {
    ["^"] = true,
    [".."] = true,
}

local render_expr: function(RenderContext, parser.Node, integer): doc.Doc
local wrap_for_parent_precedence: function(
    doc.Doc, string, integer, integer
): doc.Doc

local function render_root_expr(ctx: RenderContext, node: parser.Node): doc.Doc
    return render_expr(ctx, node, 0)
end

local function precedence_for_op(op: string, arity: integer): integer
    if arity == 1 and op == "-" then
        return PRECEDENCE["unary-"]
    elseif arity == 1 and op == "~" then
        return PRECEDENCE["unary~"]
    end
    return PRECEDENCE[op]
end

local function maybe_parenthesize(
    rendered: doc.Doc,
    child: parser.Node,
    parent_op: string,
    parent_arity: integer,
    is_right_child: boolean
): doc.Doc
    if child.kind ~= "op" or child.op == nil then
        return rendered
    end

    local child_prec = precedence_for_op(child.op.op, child.op.arity)
    local parent_prec = precedence_for_op(parent_op, parent_arity)
    if child_prec == nil or parent_prec == nil then
        return rendered
    end

    local needs = child_prec < parent_prec
    if not needs and child_prec == parent_prec and parent_arity == 2 then
        if is_right_child then
            needs = not RIGHT_ASSOC[parent_op]
        else
            needs = RIGHT_ASSOC[parent_op]
        end
    end

    if needs then
        return doc.concat({doc.text("("), rendered, doc.text(")")})
    end

    return rendered
end

local function collect_top_level_logical_terms(
    node: parser.Node, operator: string, terms: {parser.Node}
)
    if node.kind == "op"
        and node.op ~= nil
        and node.op.arity == 2
        and node.op.op == operator then
        collect_top_level_logical_terms(node.e1, operator, terms)
        collect_top_level_logical_terms(node.e2, operator, terms)
        return
    end

    table.insert(terms, node)
end

local function render_top_level_logical_chain(
    ctx: RenderContext, node: parser.Node, parent_prec: integer
): doc.Doc
    local operator = node.op.op
    local operator_prec = precedence_for_op(operator, 2)
    local terms: {parser.Node} = {}
    collect_top_level_logical_terms(node, operator, terms)

    local parts: {doc.Doc} = {}
    for index, term in ipairs(terms) do
        local term_group_ref = doc.group_ref()
        table.insert(parts, term_group_ref:group(render_expr(ctx, term, operator_prec)))
        if index < #terms then
            table.insert(
                parts,
                term_group_ref:if_break(
                    doc.text(" " .. operator .. " "),
                    doc.indent(4, doc.concat({doc.line(), doc.text(operator .. " ")}))
                )
            )
        end
    end

    return wrap_for_parent_precedence(
        doc.group(doc.concat(parts)), operator, 2, parent_prec
    )
end

local function is_logical_binary_op(node: parser.Node): boolean
    return node.kind == "op"
        and node.op ~= nil
        and node.op.arity == 2
        and (node.op.op == "and" or node.op.op == "or")
end

wrap_for_parent_precedence = function(
    rendered: doc.Doc, op: string, arity: integer, parent_prec: integer
): doc.Doc
    if precedence_for_op(op, arity) < parent_prec then
        return doc.concat({doc.text("("), rendered, doc.text(")")})
    end
    return rendered
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

local function render_op(
    ctx: RenderContext, node: parser.Node, parent_prec: integer
): doc.Doc
    local op = node.op.op
    if op == "." or op == ":" then
        return doc.concat(
            {
                render_expr(ctx, node.e1, PRECEDENCE[op]),
                doc.text(op),
                doc.text(node.e2.tk),
            }
        )
    elseif op == "@index" then
        return doc.concat(
            {
                render_expr(ctx, node.e1, PRECEDENCE[op]),
                doc.text("["),
                render_root_expr(ctx, node.e2),
                doc.text("]"),
            }
        )
    elseif op == "@funcall" then
        return call_doc.build_call_expr_doc(ctx, node)
    elseif op == "as" or op == "is" then
        return doc.concat(
            {
                render_expr(ctx, node.e1, PRECEDENCE[op]),
                doc.text(" " .. op .. " "),
                type_doc.render(node.e2.casttype),
            }
        )
    elseif node.op.arity == 1 then
        local op_prec = precedence_for_op(op, 1)
        local child = maybe_parenthesize(
            render_expr(ctx, node.e1, op_prec), node.e1, op, 1, true
        )
        local rendered = doc.concat({doc.text(op == "not" and "not " or op), child})
        return wrap_for_parent_precedence(rendered, op, 1, parent_prec)
    else
        if parent_prec == 0 and is_logical_binary_op(node) then
            return render_top_level_logical_chain(ctx, node, parent_prec)
        end

        local op_prec = precedence_for_op(op, 2)
        local left_doc = render_expr(ctx, node.e1, op_prec)
        local right_doc = render_expr(ctx, node.e2, op_prec)

        local left = maybe_parenthesize(left_doc, node.e1, op, 2, false)
        local right = maybe_parenthesize(right_doc, node.e2, op, 2, true)
        local separator = doc.text(" " .. op .. " ")
        local rendered = doc.concat({left, separator, right})
        return wrap_for_parent_precedence(rendered, op, 2, parent_prec)
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
    elseif node.kind == "op" and node.op ~= nil then
        return render_op(ctx, node, parent_prec)
    end
    error("unsupported expression kind: " .. node.kind)
end

function expr_doc.render(ctx: RenderContext, node: parser.Node): doc.Doc
    return render_root_expr(ctx, node)
end

return expr_doc
