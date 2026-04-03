-- AST expression node → compact single-line string. Now never produces wrapping or line breaks.
-- Use call_doc.build_call_expr_doc / table_doc.build_table_doc when wrapping is needed.
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local signature_doc = require("formatter.signature_doc")
local table_doc = require("formatter.table_doc")

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

local function render_compact_call_args(args: parser.Node): doc.Doc
    local parts: {doc.Doc} = {}
    for i, arg_node in ipairs(args) do
        table.insert(parts, render_expr(arg_node, 0))
        if i < #args then
            table.insert(parts, doc.text(", "))
        end
    end
    return doc.concat({doc.text("("), doc.concat(parts), doc.text(")")})
end

local function render_statement(stmt: parser.Node): doc.Doc
    if stmt.kind == "return" then
        local parts: {doc.Doc} = {}
        if stmt.exps ~= nil then
            for i, exp_node in ipairs(stmt.exps) do
                table.insert(parts, render_expr(exp_node, 0))
                if i < #stmt.exps then
                    table.insert(parts, doc.text(","))
                end
            end
        end
        if #parts == 0 then
            return doc.text("return")
        end
        return doc.concat({doc.text("return "), doc.concat(parts)})
    elseif stmt.kind == "assignment" then
        local vars: {doc.Doc} = {}
        local exps: {doc.Doc} = {}
        for i, var_node in ipairs(stmt.vars) do
            table.insert(vars, render_expr(var_node, 0))
            if i < #stmt.vars then
                table.insert(vars, doc.text(", "))
            end
        end
        for i, exp_node in ipairs(stmt.exps) do
            table.insert(exps, render_expr(exp_node, 0))
            if i < #stmt.exps then
                table.insert(exps, doc.text(", "))
            end
        end
        return doc.concat({doc.concat(vars), doc.text(" = "), doc.concat(exps)})
    elseif stmt.kind == "local_declaration" then
        local vars: {doc.Doc} = {}
        local exps: {doc.Doc} = {}
        for i, var_node in ipairs(stmt.vars) do
            table.insert(vars, doc.text(var_node.tk))
            if i < #stmt.vars then
                table.insert(vars, doc.text(", "))
            end
        end
        for i, exp_node in ipairs(stmt.exps) do
            table.insert(exps, render_expr(exp_node, 0))
            if i < #stmt.exps then
                table.insert(exps, doc.text(", "))
            end
        end
        local result = doc.concat({doc.text("local "), doc.concat(vars)})
        if stmt.decltuple ~= nil and stmt.decltuple.source_text ~= nil then
            result = doc.concat({result, doc.text(stmt.decltuple.source_text)})
        end
        if #exps > 0 then
            result = doc.concat({result, doc.text(" = "), doc.concat(exps)})
        end
        return result
    end

    error("unsupported anonymous function statement: " .. stmt.kind)
end

local function render_function_expr(node: parser.Node): doc.Doc
    local sig_text = "function" .. signature_doc.render_signature_text(
        node.args, node.rets
    )

    if node.body == nil or #node.body == 0 then
        return doc.text(sig_text .. " end")
    elseif #node.body == 1 then
        return doc.concat({
            doc.text(sig_text .. " "), render_statement(node.body[1]), doc.text(" end")
        })
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
            render_expr(node.e2, 0),
            doc.text("]"),
        })
    elseif op == "@funcall" then
        return doc.concat({
            render_expr(node.e1, PRECEDENCE[op]), render_compact_call_args(node.e2)
        })
    elseif op == "as" or op == "is" then
        assert(node.e2.casttype.source_text, "missing source_text for cast type")
        return doc.concat({
            render_expr(node.e1, PRECEDENCE[op]),
            doc.text(" " .. op .. " "),
            doc.text(node.e2.casttype.source_text),
        })
    elseif node.op.arity == 1 then
        local child = maybe_parenthesize(
            render_expr(node.e1, precedence_for_op(op, 1)), node.e1, op, 1, true
        )
        local rendered = doc.concat({doc.text(op == "not" and "not " or op), child})
        if precedence_for_op(op, 1) < parent_prec then
            return doc.concat({doc.text("("), rendered, doc.text(")")})
        end
        return rendered
    else
        local left = maybe_parenthesize(
            render_expr(node.e1, precedence_for_op(op, 2)), node.e1, op, 2, false
        )
        local right = maybe_parenthesize(
            render_expr(node.e2, precedence_for_op(op, 2)), node.e2, op, 2, true
        )
        local rendered = doc.concat({left, doc.text(" " .. op .. " "), right})
        if precedence_for_op(op, 2) < parent_prec then
            return doc.concat({doc.text("("), rendered, doc.text(")")})
        end
        return rendered
    end
end

render_expr = function(node: parser.Node, parent_prec: integer): doc.Doc
    if node.kind == "variable" or node.kind == "identifier" or node.kind == "..." then
        return doc.text(node.tk)
    elseif node.kind == "string" or node.kind == "number" or node.kind == "integer" then
        return doc.text(node.tk)
    elseif node.kind == "boolean" or node.kind == "nil" then
        return doc.text(node.tk)
    elseif node.kind == "paren" then
        return doc.concat({doc.text("("), render_expr(node.e1, 0), doc.text(")")})
    elseif node.kind == "literal_table" then
        return table_doc.build_table_doc(
            node, function(child: parser.Node): doc.Doc
                return render_expr(child, 0)
            end
        )
    elseif node.kind == "function" then
        return render_function_expr(node)
    elseif node.kind == "op" and node.op ~= nil then
        return render_op(node, parent_prec)
    end

    error("unsupported expression kind: " .. node.kind)
end

function expr_doc.render_expr(node: parser.Node): doc.Doc
    return render_expr(node, 0)
end

return expr_doc
