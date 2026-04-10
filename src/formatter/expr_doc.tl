-- AST expression node → compact single-line string. Now never produces wrapping or line breaks.
-- Use call_doc.build_call_expr_doc / table_doc.build_table_doc when wrapping is needed.
local call_doc = require("formatter.call_doc")
local doc = require("formatter.doc")
local inline_stmt_doc = require("formatter.inline_stmt_doc")
local parser = require("formatter.parser")
local signature_doc = require("formatter.signature_doc")
local table_doc = require("formatter.table_doc")
local type_doc = require("formatter.type_doc")

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

local render_expr: function(parser.Node, integer): doc.Doc
local wrap_for_parent_precedence: function(
    doc.Doc, string, integer, integer
): doc.Doc

local function render_root_expr(node: parser.Node): doc.Doc
    return render_expr(node, 0)
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

local function build_call_expr_doc(node: parser.Node): doc.Doc
    return call_doc.build_call_expr_doc(node, render_root_expr)
end

local function collect_top_level_logical_terms(
    node: parser.Node, operator: string, terms: {parser.Node}
)
    if node.kind == "op"
        and node.op ~= nil
        and node.op.arity == 2
        and node.op.op == operator
    then
        collect_top_level_logical_terms(node.e1, operator, terms)
        collect_top_level_logical_terms(node.e2, operator, terms)
        return
    end

    table.insert(terms, node)
end

local function render_top_level_logical_chain(
    node: parser.Node, parent_prec: integer
): doc.Doc
    local operator = node.op.op
    local operator_prec = precedence_for_op(operator, 2)
    local terms: {parser.Node} = {}
    collect_top_level_logical_terms(node, operator, terms)

    local parts: {doc.Doc} = {}
    for index, term in ipairs(terms) do
        local term_group_ref = doc.group_ref()
        table.insert(
            parts, term_group_ref:group(render_expr(term, operator_prec))
        )
        if index < #terms then
            local default_separator = doc.indent(4, doc.concat({
                doc.line(),
                doc.text(operator .. " "),
            }))

            table.insert(parts, term_group_ref:if_break(
                doc.text(" " .. operator .. " "), default_separator
            ))
        end
    end

    return wrap_for_parent_precedence(
        doc.group(doc.concat(parts)), operator, 2, parent_prec
    )
end

local function should_render_top_level_logical_chain(node: parser.Node): boolean
    if node.kind ~= "op"
        or node.op == nil
        or node.op.arity ~= 2
        or (node.op.op ~= "and" and node.op.op ~= "or")
    then
        return false
    end

    return true
end

wrap_for_parent_precedence = function(
    rendered: doc.Doc, op: string, arity: integer, parent_prec: integer
): doc.Doc
    if precedence_for_op(op, arity) < parent_prec then
        return doc.concat({doc.text("("), rendered, doc.text(")")})
    end
    return rendered
end

local function append_return_type(
    signature: doc.Doc, return_type_doc: doc.Doc
): doc.Doc
    return doc.concat({signature, return_type_doc})
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

local function render_statement(stmt: parser.Node): doc.Doc
    if stmt.kind == "return" then
        return inline_stmt_doc.render_return_doc(stmt, render_root_expr)
    elseif stmt.kind == "assignment" then
        return inline_stmt_doc.render_assignment_doc(stmt, render_root_expr)
    elseif stmt.kind == "local_declaration" then
        return inline_stmt_doc.render_local_declaration_doc(stmt, render_root_expr)
    end

    error("unsupported anonymous function statement: " .. stmt.kind)
end

local function render_function_expr(node: parser.Node): doc.Doc
    local function return_type_doc(): doc.Doc
        if node.rets == nil or #node.rets.tuple == 0 then
            return doc.text("")
        else
            return doc.concat({doc.text(": "), type_doc.render(node.rets)})
        end
    end

    local sig_doc = append_return_type(
        signature_doc.render_signature_doc(node.args), return_type_doc()
    )

    if node.body == nil or #node.body == 0 then
        return doc.group(doc.concat({
            doc.text("function"),
            sig_doc,
            doc.line(),
            doc.text("end"),
        }))
    elseif #node.body == 1 then
        return doc.group(doc.concat({
            doc.text("function"),
            sig_doc,
            doc.indent(4, doc.concat({
                doc.line(),
                render_statement(node.body[1]),
            })),
            doc.line(),
            doc.text("end"),
        }))
    end

    error("unsupported anonymous function body shape")
end

local function render_op(node: parser.Node, parent_prec: integer): doc.Doc
    local op = node.op.op
    if op == "." or op == ":" then
        return doc.concat({
            render_expr(node.e1, PRECEDENCE[op]), doc.text(op), doc.text(node.e2.tk)
        })
    elseif op == "@index" then
        return doc.concat({
            render_expr(node.e1, PRECEDENCE[op]),
            doc.text("["),
            render_root_expr(node.e2),
            doc.text("]"),
        })
    elseif op == "@funcall" then
        return build_call_expr_doc(node)
    elseif op == "as" or op == "is" then
        return doc.concat({
            render_expr(node.e1, PRECEDENCE[op]),
            doc.text(" " .. op .. " "),
            type_doc.render(node.e2.casttype),
        })
    elseif node.op.arity == 1 then
        local op_prec = precedence_for_op(op, 1)
        local child = maybe_parenthesize(
            render_expr(node.e1, op_prec), node.e1, op, 1, true
        )
        local rendered = doc.concat({doc.text(op == "not" and "not " or op), child})
        return wrap_for_parent_precedence(rendered, op, 1, parent_prec)
    else
        if parent_prec == 0 and should_render_top_level_logical_chain(node) then
            return render_top_level_logical_chain(node, parent_prec)
        end

        local op_prec = precedence_for_op(op, 2)
        local left_doc = render_expr(node.e1, op_prec)
        local right_doc = render_expr(node.e2, op_prec)

        local left = maybe_parenthesize(left_doc, node.e1, op, 2, false)
        local right = maybe_parenthesize(right_doc, node.e2, op, 2, true)
        local separator = doc.text(" " .. op .. " ")
        local rendered = doc.concat({left, separator, right})
        if parent_prec == 0 then
            rendered = doc.group(rendered)
        end
        return wrap_for_parent_precedence(rendered, op, 2, parent_prec)
    end
end

render_expr = function(node: parser.Node, parent_prec: integer): doc.Doc
    if node.kind == "variable" or node.kind == "identifier" or node.kind == "..." then
        return doc.text(node.tk)
    elseif node.kind == "string" then
        return render_string_literal(node)
    elseif node.kind == "number" or node.kind == "integer" then
        return doc.text(node.tk)
    elseif node.kind == "boolean" or node.kind == "nil" then
        return doc.text(node.tk)
    elseif node.kind == "paren" then
        return doc.concat({doc.text("("), render_root_expr(node.e1), doc.text(")")})
    elseif node.kind == "literal_table" then
        return table_doc.build_table_doc(node, render_root_expr)
    elseif node.kind == "function" then
        return render_function_expr(node)
    elseif node.kind == "op" and node.op ~= nil then
        return render_op(node, parent_prec)
    end

    error("unsupported expression kind: " .. node.kind)
end

function expr_doc.render_expr(node: parser.Node): doc.Doc
    return render_root_expr(node)
end

function expr_doc.render_top_level_expr(node: parser.Node): doc.Doc
    if should_render_top_level_logical_chain(node) then
        return render_top_level_logical_chain(node, 0)
    end
    return render_root_expr(node)
end

return expr_doc
