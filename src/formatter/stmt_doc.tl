-- Single AST statement → doc.Doc. Returns nil for unsupported statement shapes.
local call_doc = require("formatter.call_doc")
local doc = require("formatter.doc")
local expr_doc = require("formatter.expr_doc")
local parser = require("formatter.parser")
local signature_doc = require("formatter.signature_doc")
local structural_render_analysis = require("formatter.structural_render_analysis")

local type BlockLayout = structural_render_analysis.BlockLayout
local type StatementLayout = structural_render_analysis.StatementLayout

local stmt_doc = {}

local type RenderBlock = function(parser.Node, BlockLayout | nil): doc.Doc | nil

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

local function build_exp_doc(node: parser.Node): doc.Doc
    if node.kind == "op" and node.op ~= nil and node.op.op == "@funcall" then
        return call_doc.build_call_expr_doc(node)
    end
    return doc.text(expr_doc.render_expr(node))
end

local function render_return_doc(stmt: parser.Node): doc.Doc
    if stmt.exps == nil or #stmt.exps == 0 then
        return doc.text("return")
    end

    if #stmt.exps == 1 then
        return doc.concat({doc.text("return "), build_exp_doc(stmt.exps[1])})
    end

    local parts: {string} = {}
    for _, exp_node in ipairs(stmt.exps) do
        table.insert(parts, expr_doc.render_expr(exp_node))
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

    for _, var_node in ipairs(stmt.vars) do
        if var_node.attribute ~= nil then
            return nil
        end
        table.insert(vars, var_node.tk)
    end

    local prefix = "local " .. table.concat(vars, ", ")
    if stmt.decltuple ~= nil and stmt.decltuple.source_text ~= nil then
        prefix = prefix .. stmt.decltuple.source_text
    end

    if stmt.exps == nil or #stmt.exps == 0 then
        return doc.text(prefix)
    end

    if #stmt.exps == 1 then
        return doc.concat({doc.text(prefix .. " = "), build_exp_doc(stmt.exps[1])})
    end

    local exps: {string} = {}
    for _, exp_node in ipairs(stmt.exps) do
        table.insert(exps, expr_doc.render_expr(exp_node))
    end
    return doc.text(prefix .. " = " .. table.concat(exps, ", "))
end

local function render_local_type_doc(stmt: parser.Node): doc.Doc | nil
    if stmt.var == nil or stmt.value == nil or stmt.value.kind ~= "newtype" then
        return nil
    end

    if stmt.value.newtype == nil or stmt.value.newtype.def == nil then
        return nil
    end

    local type_text = stmt.value.newtype.def.source_text
    if type_text == nil then
        return nil
    end

    return doc.text("local type " .. stmt.var.tk .. " = " .. type_text)
end

local function render_function_name(node: parser.Node): string | nil
    local function render_function_owner(owner: parser.Node): string | nil
        if owner.kind == "identifier"
            or owner.kind == "type_identifier"
            or owner.kind == "variable"
        then
            return owner.tk
        elseif owner.kind == "op"
            and owner.op ~= nil
            and owner.op.op == "."
            and owner.e1 ~= nil
            and owner.e2 ~= nil
        then
            local left = render_function_owner(owner.e1)
            if left == nil then
                return nil
            end
            return left .. "." .. owner.e2.tk
        end

        return nil
    end

    if node.kind == "local_function" and node.name ~= nil then
        return "local function " .. node.name.tk
    elseif node.kind == "global_function" and node.name ~= nil and not node.is_method then
        return "function " .. node.name.tk
    elseif node.kind == "record_function"
        and node.fn_owner ~= nil
        and node.name ~= nil
    then
        local owner = render_function_owner(node.fn_owner)
        if owner == nil then
            return nil
        end
        local separator = node.is_method and ":" or "."
        return "function " .. owner .. separator .. node.name.tk
    end

    return nil
end

local function render_function_definition_doc(
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    if node.args == nil or node.body == nil or #node.body == 0 then
        return nil
    end

    local name_prefix = render_function_name(node)
    if name_prefix is nil then
        return nil
    end

    local typed_layout: StatementLayout | nil = nil
    if not (layout is nil) then
        typed_layout = layout
    end
    local body_layout: BlockLayout | nil = nil
    if not (typed_layout is nil) then
        local non_nil_layout = typed_layout
        body_layout = non_nil_layout.body_layout
    end

    local body_doc = render_block(node.body, body_layout)
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
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    if node.if_blocks == nil then
        return nil
    end

    local parts: {doc.Doc} = {}
    for index, if_block in ipairs(node.if_blocks) do
        if if_block.body == nil then
            return nil
        end
        local if_block_layout: BlockLayout | nil = nil
        if not layout is nil then
            local if_block_layouts = layout.if_block_layouts
            if not if_block_layouts is nil then
                if_block_layout = if_block_layouts[index]
            end
        end
        local body_doc = render_block(if_block.body, if_block_layout)
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
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    if node.exp == nil or node.body == nil or #node.body == 0 then
        return nil
    end

    local typed_layout: StatementLayout | nil = nil
    if not (layout is nil) then
        typed_layout = layout
    end
    local body_layout: BlockLayout | nil = nil
    if not typed_layout is nil then
        local non_nil_layout = typed_layout
        body_layout = non_nil_layout.body_layout
    end

    local body_doc = render_block(node.body, body_layout)
    if body_doc == nil then
        return nil
    end

    return block_with_indent(
        "while " .. expr_doc.render_expr(node.exp) .. " do", body_doc, "end"
    )
end

local function render_fornum_doc(
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    if node.var == nil or node.from == nil or node.to == nil or node.body == nil or #node.body == 0 then
        return nil
    end

    local typed_layout: StatementLayout | nil = nil
    if not (layout is nil) then
        typed_layout = layout
    end
    local body_layout: BlockLayout | nil = nil
    if not (typed_layout is nil) then
        local non_nil_layout = typed_layout
        body_layout = non_nil_layout.body_layout
    end

    local body_doc = render_block(node.body, body_layout)
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
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
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

    local typed_layout: StatementLayout | nil = nil
    if not (layout is nil) then
        typed_layout = layout
    end
    local body_layout: BlockLayout | nil = nil
    if not (typed_layout is nil) then
        local non_nil_layout = typed_layout
        body_layout = non_nil_layout.body_layout
    end

    local body_doc = render_block(node.body, body_layout)
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
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    if node.body == nil or node.exp == nil or #node.body == 0 then
        return nil
    end

    local typed_layout: StatementLayout | nil = nil
    if not (layout is nil) then
        typed_layout = layout
    end
    local body_layout: BlockLayout | nil = nil
    if not (typed_layout is nil) then
        local non_nil_layout = typed_layout
        body_layout = non_nil_layout.body_layout
    end

    local body_doc = render_block(node.body, body_layout)
    if body_doc == nil then
        return nil
    end

    return block_with_indent(
        "repeat", body_doc, "until " .. expr_doc.render_expr(node.exp)
    )
end

local function render_do_doc(
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    if node.body == nil or #node.body == 0 then
        return nil
    end

    local typed_layout: StatementLayout | nil = nil
    if not (layout is nil) then
        typed_layout = layout
    end
    local body_layout: BlockLayout | nil = nil
    if not (typed_layout is nil) then
        local non_nil_layout = typed_layout
        body_layout = non_nil_layout.body_layout
    end

    local body_doc = render_block(node.body, body_layout)
    if body_doc == nil then
        return nil
    end

    return block_with_indent("do", body_doc, "end")
end

function stmt_doc.render_statement_doc(
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    local end_line = node_end_line(node)

    if node.kind == "return" and end_line == node.y then
        return render_return_doc(node)
    elseif node.kind == "assignment" and end_line == node.y then
        return render_assignment_doc(node)
    elseif node.kind == "local_declaration" and end_line == node.y then
        return render_local_declaration_doc(node)
    elseif node.kind == "local_type" then
        return render_local_type_doc(node)
    elseif (
        node.kind == "local_function"
        or node.kind == "global_function"
        or node.kind == "record_function"
    )
        and end_line > node.y
    then
        return render_function_definition_doc(node, render_block, layout)
    elseif node.kind == "if" and end_line > node.y then
        return render_if_doc(node, render_block, layout)
    elseif node.kind == "while" and end_line > node.y then
        return render_while_doc(node, render_block, layout)
    elseif node.kind == "fornum" and end_line > node.y then
        return render_fornum_doc(node, render_block, layout)
    elseif node.kind == "forin" and end_line > node.y then
        return render_forin_doc(node, render_block, layout)
    elseif node.kind == "repeat" and end_line > node.y then
        return render_repeat_doc(node, render_block, layout)
    elseif node.kind == "do" and end_line > node.y then
        return render_do_doc(node, render_block, layout)
    elseif node.kind == "break" then
        return doc.text("break")
    elseif node.kind == "op" and end_line == node.y then
        return doc.text(expr_doc.render_expr(node))
    end

    return nil
end

return stmt_doc
