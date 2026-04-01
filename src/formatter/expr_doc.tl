local parser = require("formatter.parser")
local signature_doc = require("formatter.signature_doc")

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

local render_expr: function(parser.Node, integer): string

local function precedence_for_op(op: string, arity: integer): integer
    if arity == 1 and op == "-" then
        return PRECEDENCE["unary-"]
    elseif arity == 1 and op == "~" then
        return PRECEDENCE["unary~"]
    end
    return PRECEDENCE[op]
end

local function maybe_parenthesize(
    rendered: string,
    child: parser.Node,
    parent_op: string,
    parent_arity: integer,
    is_right_child: boolean
): string
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
        return "(" .. rendered .. ")"
    end

    return rendered
end

local function render_compact_table(node: parser.Node): string
    local parts: {string} = {}

    for _, item in ipairs(node) do
        local text: string
        if item.key_parsed == "implicit" then
            text = render_expr(item.value, 0)
        elseif item.key_parsed == "short" then
            local key_text = item.key.conststr or item.key.tk
            if item.itemtype ~= nil then
                text = key_text
                    .. ": "
                    .. assert(
                        item.itemtype.source_text,
                        "missing source_text for table item type"
                    )
                    .. " = "
                    .. render_expr(item.value, 0)
            else
                text = key_text .. " = " .. render_expr(item.value, 0)
            end
        else
            text = "["
                .. render_expr(item.key, 0)
                .. "] = "
                .. render_expr(item.value, 0)
        end
        table.insert(parts, text)
    end

    return "{" .. table.concat(parts, ", ") .. "}"
end

local function render_compact_call_args(args: parser.Node): string
    local parts: {string} = {}
    for _, arg_node in ipairs(args) do
        table.insert(parts, render_expr(arg_node, 0))
    end
    return "(" .. table.concat(parts, ", ") .. ")"
end

local function render_statement(stmt: parser.Node): string
    if stmt.kind == "return" then
        local parts: {string} = {}
        if stmt.exps ~= nil then
            for _, exp_node in ipairs(stmt.exps) do
                table.insert(parts, render_expr(exp_node, 0))
            end
        end
        if #parts == 0 then
            return "return"
        end
        return "return " .. table.concat(parts, ", ")
    elseif stmt.kind == "assignment" then
        local vars: {string} = {}
        local exps: {string} = {}
        for _, var_node in ipairs(stmt.vars) do
            table.insert(vars, render_expr(var_node, 0))
        end
        for _, exp_node in ipairs(stmt.exps) do
            table.insert(exps, render_expr(exp_node, 0))
        end
        return table.concat(vars, ", ") .. " = " .. table.concat(exps, ", ")
    elseif stmt.kind == "local_declaration" then
        local vars: {string} = {}
        local exps: {string} = {}
        for _, var_node in ipairs(stmt.vars) do
            table.insert(vars, var_node.tk)
        end
        for _, exp_node in ipairs(stmt.exps) do
            table.insert(exps, render_expr(exp_node, 0))
        end
        local result = "local " .. table.concat(vars, ", ")
        if stmt.decltuple ~= nil and stmt.decltuple.source_text ~= nil then
            result = result .. stmt.decltuple.source_text
        end
        if #exps > 0 then
            result = result .. " = " .. table.concat(exps, ", ")
        end
        return result
    end

    error("unsupported anonymous function statement: " .. stmt.kind)
end

local function render_function_expr(node: parser.Node): string
    local result = "function" .. signature_doc.render_signature_text(
        node.args, node.rets
    )

    if node.body == nil or #node.body == 0 then
        return result .. " end"
    elseif #node.body == 1 then
        return result .. " " .. render_statement(node.body[1]) .. " end"
    end

    error("unsupported anonymous function body shape")
end

local function render_op(node: parser.Node, parent_prec: integer): string
    local op = node.op.op
    if op == "." or op == ":" then
        return render_expr(node.e1, PRECEDENCE[op]) .. op .. node.e2.tk
    elseif op == "@index" then
        return render_expr(node.e1, PRECEDENCE[op])
            .. "["
            .. render_expr(node.e2, 0)
            .. "]"
    elseif op == "@funcall" then
        return render_expr(node.e1, PRECEDENCE[op]) .. render_compact_call_args(node.e2)
    elseif op == "as" or op == "is" then
        return render_expr(node.e1, PRECEDENCE[op])
            .. " "
            .. op
            .. " "
            .. assert(node.e2.casttype.source_text, "missing source_text for cast type")
    elseif node.op.arity == 1 then
        local child = maybe_parenthesize(
            render_expr(node.e1, precedence_for_op(op, 1)), node.e1, op, 1, true
        )
        local rendered = (op == "not" and "not " or op) .. child
        if precedence_for_op(op, 1) < parent_prec then
            return "(" .. rendered .. ")"
        end
        return rendered
    else
        local left = maybe_parenthesize(
            render_expr(node.e1, precedence_for_op(op, 2)), node.e1, op, 2, false
        )
        local right = maybe_parenthesize(
            render_expr(node.e2, precedence_for_op(op, 2)), node.e2, op, 2, true
        )
        local rendered = left .. " " .. op .. " " .. right
        if precedence_for_op(op, 2) < parent_prec then
            return "(" .. rendered .. ")"
        end
        return rendered
    end
end

render_expr = function(node: parser.Node, parent_prec: integer): string
    if node.kind == "variable" or node.kind == "identifier" or node.kind == "..." then
        return node.tk
    elseif node.kind == "string" or node.kind == "number" or node.kind == "integer" then
        return node.tk
    elseif node.kind == "boolean" or node.kind == "nil" then
        return node.tk
    elseif node.kind == "paren" then
        return "(" .. render_expr(node.e1, 0) .. ")"
    elseif node.kind == "literal_table" then
        return render_compact_table(node)
    elseif node.kind == "function" then
        return render_function_expr(node)
    elseif node.kind == "op" and node.op ~= nil then
        return render_op(node, parent_prec)
    end

    error("unsupported expression kind: " .. node.kind)
end

function expr_doc.render_expr(node: parser.Node): string
    return render_expr(node, 0)
end

return expr_doc
