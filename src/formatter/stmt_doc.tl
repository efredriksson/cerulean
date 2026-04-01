local doc = require("formatter.doc")
local expr_doc = require("formatter.expr_doc")
local parser = require("formatter.parser")
local signature_doc = require("formatter.signature_doc")

local stmt_doc = {}

local type RenderBlock = function(parser.Node): doc.Doc | nil

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function block_with_indent(
    header_text: string, body: doc.Doc, footer_text: string
): doc.Doc
    return doc.concat({
        doc.text(header_text),
        doc.indent(4, doc.concat({
            doc.line(""),
            body,
        })),
        doc.line(""),
        doc.text(footer_text),
    })
end

local function render_return_doc(stmt: parser.Node): doc.Doc
    local parts: {string} = {}
    if stmt.exps ~= nil then
        for _, exp_node in ipairs(stmt.exps) do
            table.insert(parts, expr_doc.render_expr(exp_node))
        end
    end

    if #parts == 0 then
        return doc.text("return")
    end

    return doc.text("return " .. table.concat(parts, ", "))
end

local function render_assignment_doc(stmt: parser.Node): doc.Doc
    local vars: {string} = {}
    local exps: {string} = {}

    for _, var_node in ipairs(stmt.vars) do
        table.insert(vars, expr_doc.render_expr(var_node))
    end
    for _, exp_node in ipairs(stmt.exps) do
        table.insert(exps, expr_doc.render_expr(exp_node))
    end

    return doc.text(table.concat(vars, ", ") .. " = " .. table.concat(exps, ", "))
end

local function render_local_declaration_doc(stmt: parser.Node): doc.Doc | nil
    local vars: {string} = {}
    local exps: {string} = {}

    for _, var_node in ipairs(stmt.vars) do
        if var_node.attribute ~= nil then
            return nil
        end
        table.insert(vars, var_node.tk)
    end
    for _, exp_node in ipairs(stmt.exps) do
        table.insert(exps, expr_doc.render_expr(exp_node))
    end

    local result = "local " .. table.concat(vars, ", ")
    if stmt.decltuple ~= nil and stmt.decltuple.source_text ~= nil then
        result = result .. stmt.decltuple.source_text
    end
    if #exps > 0 then
        result = result .. " = " .. table.concat(exps, ", ")
    end

    return doc.text(result)
end

local function render_local_type_doc(stmt: parser.Node): doc.Doc | nil
    if stmt.var == nil or stmt.value == nil or stmt.value.kind ~= "op" then
        return nil
    end

    return doc.text("local type " .. stmt.var.tk .. " = " .. expr_doc.render_expr(stmt.value))
end

local function render_function_name(node: parser.Node): string | nil
    if node.kind == "local_function" and node.name ~= nil then
        return "local function " .. node.name.tk
    elseif node.kind == "global_function" and node.name ~= nil and not node.is_method then
        return "function " .. node.name.tk
    end

    return nil
end

local function render_function_definition_doc(
    node: parser.Node, render_block: RenderBlock
): doc.Doc | nil
    if node.args == nil or node.body == nil or #node.body == 0 then
        return nil
    end

    local name_prefix = render_function_name(node)
    if name_prefix == nil then
        return nil
    end

    local body_doc = render_block(node.body)
    if body_doc == nil then
        return nil
    end

    return block_with_indent(
        name_prefix .. signature_doc.render_signature_text(node.args, node.rets),
        body_doc,
        "end"
    )
end

local function render_if_doc(
    node: parser.Node, render_block: RenderBlock
): doc.Doc | nil
    if node.if_blocks == nil then
        return nil
    end

    local parts: {doc.Doc} = {}
    for index, if_block in ipairs(node.if_blocks) do
        if if_block.body == nil then
            return nil
        end
        local body_doc = render_block(if_block.body)
        if body_doc == nil then
            return nil
        end

        local header_text: string
        if if_block.exp ~= nil then
            if index == 1 then
                header_text = "if " .. expr_doc.render_expr(if_block.exp) .. " then"
            else
                header_text = "elseif " .. expr_doc.render_expr(if_block.exp) .. " then"
            end
        else
            header_text = "else"
        end

        if index > 1 then
            table.insert(parts, doc.line(""))
        end
        table.insert(parts, doc.text(header_text))
        table.insert(parts, doc.indent(4, doc.concat({
            doc.line(""),
            body_doc,
        })))
    end

    table.insert(parts, doc.line(""))
    table.insert(parts, doc.text("end"))
    return doc.concat(parts)
end

local function render_while_doc(
    node: parser.Node, render_block: RenderBlock
): doc.Doc | nil
    if node.exp == nil or node.body == nil or #node.body == 0 then
        return nil
    end

    local body_doc = render_block(node.body)
    if body_doc == nil then
        return nil
    end

    return block_with_indent(
        "while " .. expr_doc.render_expr(node.exp) .. " do", body_doc, "end"
    )
end

local function render_fornum_doc(
    node: parser.Node, render_block: RenderBlock
): doc.Doc | nil
    if node.var == nil or node.from == nil or node.to == nil or node.body == nil or #node.body == 0 then
        return nil
    end

    local body_doc = render_block(node.body)
    if body_doc == nil then
        return nil
    end

    local header = "for "
        .. node.var.tk
        .. " = "
        .. expr_doc.render_expr(node.from)
        .. ", "
        .. expr_doc.render_expr(node.to)
    if node.step ~= nil then
        header = header .. ", " .. expr_doc.render_expr(node.step)
    end

    return block_with_indent(header .. " do", body_doc, "end")
end

local function render_forin_doc(
    node: parser.Node, render_block: RenderBlock
): doc.Doc | nil
    if node.vars == nil or node.exps == nil or node.body == nil or #node.body == 0 then
        return nil
    end

    local vars: {string} = {}
    local exps: {string} = {}
    for _, var_node in ipairs(node.vars) do
        table.insert(vars, var_node.tk)
    end
    for _, exp_node in ipairs(node.exps) do
        table.insert(exps, expr_doc.render_expr(exp_node))
    end

    local body_doc = render_block(node.body)
    if body_doc == nil then
        return nil
    end

    local header = "for "
        .. table.concat(vars, ", ")
        .. " in "
        .. table.concat(exps, ", ")
        .. " do"

    return block_with_indent(header, body_doc, "end")
end

local function render_repeat_doc(
    node: parser.Node, render_block: RenderBlock
): doc.Doc | nil
    if node.body == nil or node.exp == nil or #node.body == 0 then
        return nil
    end

    local body_doc = render_block(node.body)
    if body_doc == nil then
        return nil
    end

    return block_with_indent(
        "repeat", body_doc, "until " .. expr_doc.render_expr(node.exp)
    )
end

local function render_do_doc(
    node: parser.Node, render_block: RenderBlock
): doc.Doc | nil
    if node.body == nil or #node.body == 0 then
        return nil
    end

    local body_doc = render_block(node.body)
    if body_doc == nil then
        return nil
    end

    return block_with_indent("do", body_doc, "end")
end

function stmt_doc.render_statement_doc(
    node: parser.Node, render_block: RenderBlock
): doc.Doc | nil
    local end_line = node_end_line(node)

    if node.kind == "return" and end_line == node.y then
        return render_return_doc(node)
    elseif node.kind == "assignment" and end_line == node.y then
        return render_assignment_doc(node)
    elseif node.kind == "local_declaration" and end_line == node.y then
        return render_local_declaration_doc(node)
    elseif node.kind == "local_type" and end_line == node.y then
        return render_local_type_doc(node)
    elseif (node.kind == "local_function" or node.kind == "global_function")
        and end_line > node.y
    then
        return render_function_definition_doc(node, render_block)
    elseif node.kind == "if" and end_line > node.y then
        return render_if_doc(node, render_block)
    elseif node.kind == "while" and end_line > node.y then
        return render_while_doc(node, render_block)
    elseif node.kind == "fornum" and end_line > node.y then
        return render_fornum_doc(node, render_block)
    elseif node.kind == "forin" and end_line > node.y then
        return render_forin_doc(node, render_block)
    elseif node.kind == "repeat" and end_line > node.y then
        return render_repeat_doc(node, render_block)
    elseif node.kind == "do" and end_line > node.y then
        return render_do_doc(node, render_block)
    elseif node.kind == "break" then
        return doc.text("break")
    elseif node.kind == "op" and end_line == node.y then
        return doc.text(expr_doc.render_expr(node))
    end

    return nil
end

return stmt_doc
