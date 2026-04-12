-- Single AST statement → doc.Doc. Returns nil for unsupported statement shapes.
local call_doc = require("formatter.call_doc")
local doc = require("formatter.doc")
local expr_doc = require("formatter.expr_doc")
local parser = require("formatter.parser")
local signature_doc = require("formatter.signature_doc")
local structural_render_analysis = require("formatter.structural_render_analysis")
local tl = require("tl")

local type BlockLayout = structural_render_analysis.BlockLayout
local type StatementLayout = structural_render_analysis.StatementLayout

local stmt_doc = {}

local type RenderBlock = function(parser.Node, BlockLayout | nil): doc.Doc | nil

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function function_with_indent(
    name_prefix: string, signature: doc.Doc, body: doc.Doc
): doc.Doc
    return doc.concat({
        doc.text(name_prefix),
        signature,
        doc.indent(4, doc.concat({
            doc.line(""),
            body,
        })),
        doc.close("end"),
    })
end

local function block_with_indent(
    header: doc.Doc, body: doc.Doc, footer: doc.Doc
): doc.Doc
    return doc.concat({
        header,
        doc.indent(4, doc.concat({
            doc.line(""),
            body,
        })),
        doc.line(""),
        footer,
    })
end

local function block_with_close(
    header: doc.Doc, body: doc.Doc, close_text: string
): doc.Doc
    return doc.concat({
        header,
        doc.indent(4, doc.concat({
            doc.line(""),
            body,
        })),
        doc.close(close_text),
    })
end

local function build_exp_doc(node: parser.Node): doc.Doc
    if node.kind == "op" and node.op ~= nil and node.op.op == "@funcall" then
        return call_doc.build_call_expr_doc(node)
    end
    return expr_doc.render_expr(node)
end

local function render_return_doc(stmt: parser.Node): doc.Doc
    if stmt.exps == nil or #stmt.exps == 0 then
        return doc.text("return")
    end

    if #stmt.exps == 1 then
        return doc.concat({doc.text("return "), build_exp_doc(stmt.exps[1])})
    end

    local parts: {doc.Doc} = {}
    for i, exp_node in ipairs(stmt.exps) do
        table.insert(parts, build_exp_doc(exp_node))
        if i < #stmt.exps then
            table.insert(parts, doc.text(", "))
        end
    end
    return doc.concat({doc.text("return "), doc.concat(parts)})
end

local function render_assignment_doc(stmt: parser.Node): doc.Doc
    local vars: {doc.Doc} = {}

    for i, var_node in ipairs(stmt.vars) do
        table.insert(vars, build_exp_doc(var_node))
        if i < #stmt.vars then
            table.insert(vars, doc.text(", "))
        end
    end

    local lhs_doc = doc.concat({doc.concat(vars), doc.text(" = ")})

    local exps: {doc.Doc} = {}
    for i, exp_node in ipairs(stmt.exps) do
        table.insert(exps, build_exp_doc(exp_node))
        if i < #stmt.exps then
            table.insert(exps, doc.text(", "))
        end
    end

    return doc.concat({lhs_doc, doc.concat(exps)})
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

    local exps: {doc.Doc} = {}
    for i, exp_node in ipairs(stmt.exps) do
        table.insert(exps, build_exp_doc(exp_node))
        if i < #stmt.exps then
            table.insert(exps, doc.text(", "))
        end
    end
    return doc.concat({doc.text(prefix .. " = "), doc.concat(exps)})
end

local record RecordItemDoc
    item: parser.Node
    type_text: string
    comment: tl.LexerComment
end

function RecordItemDoc.new(
    item: parser.Node, type_text: string, comment: tl.LexerComment
): RecordItemDoc
    local self: RecordItemDoc = setmetatable({}, {__index = RecordItemDoc})
    self.item = item
    self.type_text = type_text
    self.comment = comment
    return self
end

local function render_local_record_doc(stmt: parser.Node): doc.Doc | nil
    if stmt.var == nil or stmt.value == nil then
        return nil
    end
    local newtype = stmt.value.newtype
    if newtype == nil then
        return nil
    end
    local def = newtype.def
    local declaration_keyword: string
    local record_def: tl.RecordLikeType
    local is_type_declaration = stmt.is_type_declaration
    local typeargs_str = ""
    if def is tl.GenericType then
        local parts: {string} = {}
        for _, typearg in ipairs(def.typeargs) do
            table.insert(parts, typearg.typearg)
        end
        typeargs_str = "<" .. table.concat(parts, ", ") .. ">"
        def = def.t
        if def == nil then
            return nil
        end
    end
    if def is tl.InterfaceType then
        declaration_keyword = "interface"
        record_def = def
    elseif def is tl.RecordType then
        declaration_keyword = "record"
        record_def = def
    else
        return nil
    end

    local function render_record_interface_doc(iface: tl.Type): doc.Doc | nil
        if iface.source_text ~= nil and iface.source_text ~= "" then
            return doc.text(iface.source_text)
        end

        if iface is tl.NominalType then
            local parts: {doc.Doc} = {
                doc.text(table.concat(iface.names, ".")),
            }
            if iface.typevals ~= nil and #iface.typevals > 0 then
                table.insert(parts, doc.text("<"))
                for index, typeval in ipairs(iface.typevals) do
                    if typeval.source_text == nil or typeval.source_text == "" then
                        return nil
                    end
                    table.insert(parts, doc.text(typeval.source_text))
                    if index < #iface.typevals then
                        table.insert(parts, doc.text(", "))
                    end
                end
                table.insert(parts, doc.text(">"))
            end
            return doc.concat(parts)
        elseif iface is tl.ArrayType then
            if iface.elements == nil or iface.elements.source_text == nil then
                return nil
            end
            return doc.concat({
                doc.text("{"),
                doc.text(iface.elements.source_text),
                doc.text("}"),
            })
        end

        return nil
    end

    local header_parts: {doc.Doc} = {
        doc.text(
            is_type_declaration and ("local type " .. stmt.var.tk .. typeargs_str .. " = " .. declaration_keyword) or ("local " .. declaration_keyword .. " " .. stmt.var.tk .. typeargs_str)
        ),
    }
    if record_def.interface_list ~= nil and #record_def.interface_list > 0 then
        table.insert(header_parts, doc.text(" is "))
        for index, iface in ipairs(record_def.interface_list) do
            local iface_doc = render_record_interface_doc(iface)
            if iface_doc == nil then
                return nil
            end
            table.insert(header_parts, iface_doc)
            if index < #record_def.interface_list then
                table.insert(header_parts, doc.text(", "))
            end
        end
    end
    if declaration_keyword == "interface"
        and record_def.meta_fields ~= nil
        and record_def.meta_fields["__is"] ~= nil
    then
        local where_function = record_def.meta_fields["__is"]
        if not (where_function is tl.FunctionType) or where_function.macroexp == nil then
            return nil
        end
        local where_macroexp = where_function.macroexp as parser.Node
        if where_macroexp.exp == nil then
            return nil
        end
        table.insert(header_parts, doc.text(" where "))
        table.insert(header_parts, build_exp_doc(where_macroexp.exp))
    end

    local record_lines: {RecordItemDoc} = {}
    local previous_item: RecordItemDoc | nil = nil

    local function comment_after_prev_item(comment: tl.LexerComment): RecordItemDoc | nil
        if previous_item is nil then
            return nil
        end

        local previous_item_line = previous_item.item.yend or previous_item.item.y
        if previous_item_line == comment.y then
            return previous_item
        end

        return nil
    end

    for _, field_name in ipairs(record_def.field_order) do
        local field_type = record_def.fields[field_name]
        if field_type == nil or field_type.source_text == nil then
            return nil
        end

        local field_comments = (record_def.field_comments or {})[field_name] or {}
        for _, c1 in ipairs(field_comments) do
            for _, c2 in ipairs(c1) do
                local attacted_to_item = comment_after_prev_item(c2)
                if not (attacted_to_item is nil) then
                    if not (attacted_to_item is nil) then
                        attacted_to_item.comment = c2
                    else
                        table.insert(record_lines, RecordItemDoc.new(nil, nil, c2))
                    end
                end
            end
        end

        local field_text = field_name .. ": " .. field_type.source_text
        local record_item = RecordItemDoc.new(
            field_type as parser.Node, field_text, nil
        )
        table.insert(record_lines, record_item)
        previous_item = record_item
    end

    for _, comment in ipairs(stmt.end_comments or {}) do
        local attacted_to_item = comment_after_prev_item(comment)
       -- TODO: code duplication!
        if not (attacted_to_item is nil) then
            attacted_to_item.comment = comment
        else
            table.insert(record_lines, RecordItemDoc.new(nil, nil, comment))
        end
    end

    local field_docs: {doc.Doc} = {}

    for _, record_line in ipairs(record_lines) do
        if record_line.comment ~= nil and record_line.item == nil then
            table.insert(field_docs, doc.text(record_line.comment.text))
            table.insert(field_docs, doc.hardline())
        elseif record_line.comment == nil and record_line.item ~= nil then
            table.insert(field_docs, doc.text(record_line.type_text))
            table.insert(field_docs, doc.line(""))
        elseif record_line.comment ~= nil and record_line.item ~= nil then
            table.insert(
                field_docs,
                doc.text(record_line.type_text .. " " .. record_line.comment.text)
            )
            table.insert(field_docs, doc.line(""))
        end
    end

    return doc.concat({
        doc.concat(header_parts),
        doc.indent(4, doc.concat({
            doc.line(""),
            doc.concat(field_docs),
        })),
        doc.close("end"),
    })
end

local function render_local_type_doc(stmt: parser.Node): doc.Doc | nil
    if stmt.var == nil or stmt.value == nil then
        return nil
    end
    if stmt.value.kind ~= "newtype" then
        return doc.concat({
            doc.text("local type " .. stmt.var.tk .. " = "), build_exp_doc(stmt.value)
        })
    end

    if stmt.value.newtype == nil or stmt.value.newtype.def == nil then
        return nil
    end

    local def = stmt.value.newtype.def
    if def.typename == "record" or def.typename == "interface" or def.typename == "generic" then
        return render_local_record_doc(stmt)
    end

    local type_text = stmt.value.newtype.def.source_text
    if type_text ~= nil then
        return doc.text("local type " .. stmt.var.tk .. " = " .. type_text)
    end

    return render_local_record_doc(stmt)
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

    local function render_function_typeargs(fn_node: parser.Node): string
        if fn_node.typeargs == nil or #fn_node.typeargs == 0 then
            return ""
        end
        local parts: {string} = {}
        for _, typearg in ipairs(fn_node.typeargs) do
            table.insert(parts, typearg.typearg)
        end
        return "<" .. table.concat(parts, ", ") .. ">"
    end

    if node.kind == "local_function" and node.name ~= nil then
        return "local function " .. node.name.tk .. render_function_typeargs(node)
    elseif node.kind == "global_function" and node.name ~= nil and not node.is_method then
        return "function " .. node.name.tk .. render_function_typeargs(node)
    elseif node.kind == "record_function"
        and node.fn_owner ~= nil
        and node.name ~= nil
    then
        local owner = render_function_owner(node.fn_owner)
        if owner == nil then
            return nil
        end
        local separator = node.is_method and ":" or "."
        return "function " .. owner .. separator .. node.name.tk .. render_function_typeargs(
            node
        )
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

    local sig_doc = signature_doc.render_signature_doc(node.args, true)
    if node.rets ~= nil and node.rets.source_text ~= nil and node.rets.source_text ~= "" then
        sig_doc = doc.concat({sig_doc, doc.text(node.rets.source_text)})
    end
    return function_with_indent(name_prefix, sig_doc, body_doc)
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

        local function get_head_text(): doc.Doc
            if if_block.exp ~= nil then
                if index == 1 then
                    return doc.concat({
                        doc.text("if "),
                        build_exp_doc(if_block.exp),
                        doc.text(" then"),
                    })
                else
                    return doc.concat({
                        doc.text("elseif "),
                        build_exp_doc(if_block.exp),
                        doc.text(" then"),
                    })
                end
            else
                return doc.text("else")
            end
        end

        if index > 1 then
            table.insert(parts, doc.line(""))
        end
        table.insert(parts, get_head_text())
        table.insert(parts, doc.indent(4, doc.concat({
            doc.line(""),
            body_doc,
        })))
    end

    table.insert(parts, doc.close("end"))
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

    local header = doc.concat({
        doc.text("while "), build_exp_doc(node.exp), doc.text(" do")
    })
    return block_with_close(header, body_doc, "end")
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

    local pre_header = doc.text("for " .. node.var.tk .. " = ")
    local header = doc.concat({
        pre_header,
        build_exp_doc(node.from),
        doc.text(", "),
        build_exp_doc(node.to),
    })
    if node.step ~= nil then
        header = doc.concat({header, doc.text(", "), build_exp_doc(node.step)})
    end

    return block_with_close(doc.concat({header, doc.text(" do")}), body_doc, "end")
end

local function render_forin_doc(
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    if node.vars == nil or node.exps == nil or node.body == nil or #node.body == 0 then
        return nil
    end

    local vars: {doc.Doc} = {}
    local exps: {doc.Doc} = {}
    for i, var_node in ipairs(node.vars) do
        table.insert(vars, doc.text(var_node.tk))
        if i < #node.vars then
            table.insert(vars, doc.text(", "))
        end
    end
    for i, exp_node in ipairs(node.exps) do
        table.insert(exps, build_exp_doc(exp_node))
        if i < #node.exps then
            table.insert(exps, doc.text(", "))
        end
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

    local header = doc.concat({
        doc.text("for "),
        doc.concat(vars),
        doc.text(" in "),
        doc.concat(exps),
        doc.text(" do"),
    })
    return block_with_close(header, body_doc, "end")
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
    if body_doc is nil then
        return nil
    end

    return block_with_indent(
        doc.text("repeat"), body_doc, doc.concat({
            doc.text("until "), build_exp_doc(node.exp)
        })
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

    return block_with_close(doc.text("do"), body_doc, "end")
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
    elseif node.kind == "op" then
        if node.op ~= nil and node.op.op == "@funcall" then
            return call_doc.build_call_expr_doc(node)
        end
        if end_line == node.y then
            return build_exp_doc(node)
        end
    end

    return nil
end

return stmt_doc
