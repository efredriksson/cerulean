-- Single AST statement → doc.Doc. Returns nil for unsupported statement shapes.
local doc = require("formatter.doc")
local expr_doc = require("formatter.expr_doc")
local inline_stmt_doc = require("formatter.inline_stmt_doc")
local layout_types = require("formatter.layout_types")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local signature_doc = require("formatter.signature_doc")

local type BlockLayout = layout_types.BlockLayout
local type StatementLayout = layout_types.StatementLayout

local stmt_doc = {}

local type RenderBlock = function(parser.Node, BlockLayout | nil): doc.Doc | nil

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function get_body_layout(layout: StatementLayout | nil): BlockLayout | nil
    if layout is nil then
        return nil
    end
    return layout.body_layout
end

local function render_type_constraint_text(constraint: parser.Type): string | nil
    if constraint.source_text ~= nil and constraint.source_text ~= "" then
        return constraint.source_text
    end

    if constraint is parser.NominalType then
        local parts: {string} = {table.concat(constraint.names, ".")}
        if constraint.typevals ~= nil and #constraint.typevals > 0 then
            local typevals: {string} = {}
            for _, typeval in ipairs(constraint.typevals) do
                if typeval.source_text == nil or typeval.source_text == "" then
                    return nil
                end
                table.insert(typevals, typeval.source_text)
            end
            table.insert(parts, "<" .. table.concat(typevals, ", ") .. ">")
        end
        return table.concat(parts)
    end

    return nil
end

local function render_typearg_list(typeargs: {parser.TypeArgType}): string
    if #typeargs == 0 then
        return ""
    end

    local parts: {string} = {}
    for _, typearg in ipairs(typeargs) do
        local typearg_text = typearg.typearg
        if typearg.constraint ~= nil then
            local constraint_text = render_type_constraint_text(typearg.constraint)
            if not (constraint_text is nil) then
                typearg_text = typearg_text .. " is " .. constraint_text
            end
        end
        table.insert(parts, typearg_text)
    end
    return "<" .. table.concat(parts, ", ") .. ">"
end

local function with_indented_body(
    header: doc.Doc, body: doc.Doc, tail: doc.Doc
): doc.Doc
    return doc.concat(
        {
            header,
            doc.indent(
                4,
                doc.concat(
                    {
                        doc.line(),
                        body,
                    }
                )
            ),
            tail,
        }
    )
end

local function function_with_indent(
    name_prefix: string, signature: doc.Doc, body: doc.Doc
): doc.Doc
    local header = doc.group(
        doc.concat(
            {
                doc.text(name_prefix),
                signature,
            }
        )
    )
    return with_indented_body(header, body, doc.close("end"))
end

local function block_with_indent(
    header: doc.Doc, body: doc.Doc, footer: doc.Doc
): doc.Doc
    return with_indented_body(header, body, doc.concat({doc.line(), footer}))
end

local function block_with_close(
    header: doc.Doc, body: doc.Doc, close_text: string
): doc.Doc
    return with_indented_body(header, body, doc.close(close_text))
end

local function build_exp_doc(node: parser.Node): doc.Doc
    return expr_doc.render_expr(node)
end

local function append_return_type(signature: doc.Doc, rets_source_text: string): doc.Doc
    if rets_source_text ~= "" then
        return doc.group(doc.concat({signature, doc.text(rets_source_text)}))
    end
    return signature
end

local function build_control_flow_head_doc(
    head_keyword: string, exp: parser.Node, tail_text: string
): doc.Doc
    return doc.group(
        doc.concat(
            {
                doc.text(head_keyword .. " "),
                expr_doc.render_top_level_expr(exp),
                doc.text(tail_text),
            }
        )
    )
end

local function render_return_doc(stmt: parser.Node): doc.Doc
    return inline_stmt_doc.render_return_doc(stmt, build_exp_doc)
end

local function render_assignment_doc(stmt: parser.Node): doc.Doc
    return inline_stmt_doc.render_assignment_doc(stmt, build_exp_doc)
end

local function render_local_declaration_doc(stmt: parser.Node): doc.Doc | nil
    return inline_stmt_doc.render_local_declaration_doc(stmt, build_exp_doc)
end

local function render_enum_doc(stmt: parser.Node, def: parser.EnumType): doc.Doc
    local header: doc.Doc
    if stmt.is_type_declaration then
        header = doc.text("local type " .. def.declname .. " = enum")
    else
        header = doc.text("local enum " .. def.declname)
    end

    local enum_items = render_builders.CommentLineItems.new()
    local previous_item_line = stmt.y

    for _, enum_str in ipairs(def.enumset) do
        local item_line = previous_item_line + 1
        local comments = ((def.value_comments or {})[enum_str] or {})
        for _, comment in ipairs(comments) do
            if comment.y >= item_line then
                item_line = comment.y + 1
            end
        end
        enum_items:add(doc.text('"' .. enum_str .. '"'), item_line, comments, false)
        previous_item_line = item_line
    end

    local enum_end_comments: {parser.Comment} = {}
    if def.end_comments ~= nil then
        enum_end_comments = def.end_comments
    elseif stmt.end_comments ~= nil then
        enum_end_comments = stmt.end_comments
    end
    enum_items:add_end_comments(enum_end_comments)

    return block_with_close(
        header, render_builders.render_line_entries(enum_items, nil, nil), "end"
    )
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
    local record_def: parser.RecordLikeType
    local is_type_declaration = stmt.is_type_declaration
    local typeargs_str = ""

    if def is parser.GenericType then
        local generic_def = def
        typeargs_str = render_typearg_list(generic_def.typeargs or {})
        def = generic_def.t
        if def == nil then
            return nil
        end
    end
    if def is parser.InterfaceType then
        declaration_keyword = "interface"
        record_def = def
    elseif def is parser.RecordType then
        declaration_keyword = "record"
        record_def = def
    elseif def is parser.EnumType then
        return render_enum_doc(stmt, def)
    else
        return nil
    end

    local function render_record_interface_doc(iface: parser.Type): doc.Doc | nil
        if iface.source_text ~= nil and iface.source_text ~= "" then
            return doc.text(iface.source_text)
        end

        if iface is parser.NominalType then
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
        elseif iface is parser.ArrayType then
            if iface.elements == nil or iface.elements.source_text == nil then
                return nil
            end
            return doc.concat(
                {
                    doc.text("{"),
                    doc.text(iface.elements.source_text),
                    doc.text("}"),
                }
            )
        end

        return nil
    end

    local header_parts: {doc.Doc} = {
        doc.text(
            is_type_declaration and ("local type " .. stmt.var.tk .. typeargs_str .. " = " .. declaration_keyword)
                or ("local " .. declaration_keyword .. " " .. stmt.var.tk .. typeargs_str)
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
        and record_def.meta_fields["__is"] ~= nil then
        local where_function = record_def.meta_fields["__is"]
        if not (where_function is parser.FunctionType)
            or where_function.macroexp == nil then
            return nil
        end
        local where_macroexp = where_function.macroexp as parser.Node
        if where_macroexp.exp == nil then
            return nil
        end
        table.insert(header_parts, doc.text(" where "))
        table.insert(header_parts, build_exp_doc(where_macroexp.exp))
    end

    local record_items = render_builders.CommentLineItems.new()
    for _, field_name in ipairs(record_def.field_order) do
        local field_type = record_def.fields[field_name]
        if field_type == nil or field_type.source_text == nil then
            return nil
        end

        local field_comments = ((record_def.field_comments or {})[field_name]
            or {}) as {{parser.Comment}}
        local parser_comments: {parser.Comment} = {}
        for _, overload_comments in ipairs(field_comments) do
            for _, comment in ipairs(overload_comments) do
                table.insert(parser_comments, comment)
            end
        end

        local field_text = field_name .. ": " .. field_type.source_text
        record_items:add(
            doc.text(field_text),
            render_builders.node_end_line(field_type as parser.Node),
            parser_comments,
            false
        )
    end
    record_items:add_end_comments(stmt.end_comments or {})
    return doc.concat(
        {
            doc.concat(header_parts),
            doc.indent(
                4,
                doc.concat(
                    {
                        doc.line(),
                        render_builders.render_line_entries(record_items, nil, nil),
                    }
                )
            ),
            doc.close("end"),
        }
    )
end

local function render_local_type_doc(stmt: parser.Node): doc.Doc | nil
    if stmt.var == nil or stmt.value == nil then
        return nil
    end
    if stmt.value.kind ~= "newtype" then
        return doc.concat(
            {doc.text("local type " .. stmt.var.tk .. " = "), build_exp_doc(stmt.value)}
        )
    end

    if stmt.value.newtype == nil or stmt.value.newtype.def == nil then
        return nil
    end

    local def = stmt.value.newtype.def
    if def.typename == "record"
        or def.typename == "interface"
        or def.typename == "generic" then
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
            or owner.kind == "variable" then
            return owner.tk
        elseif owner.kind == "op"
            and owner.op ~= nil
            and owner.op.op == "."
            and owner.e1 ~= nil
            and owner.e2 ~= nil then
            local left = render_function_owner(owner.e1)
            if left == nil then
                return nil
            end
            return left .. "." .. owner.e2.tk
        end

        return nil
    end

    local function render_function_typeargs(fn_node: parser.Node): string
        if fn_node.typeargs == nil then
            return ""
        end
        return render_typearg_list(fn_node.typeargs)
    end

    if node.kind == "local_function" and node.name ~= nil then
        return "local function " .. node.name.tk .. render_function_typeargs(node)
    elseif node.kind == "global_function"
        and node.name ~= nil
        and not node.is_method then
        return "function " .. node.name.tk .. render_function_typeargs(node)
    elseif node.kind == "record_function"
        and node.fn_owner ~= nil
        and node.name ~= nil then
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
    if node.args == nil or node.body == nil then
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

    local rets_source_text = ""
    if node.rets ~= nil and node.rets.source_text ~= nil then
        rets_source_text = node.rets.source_text
    end

    local sig_doc = append_return_type(
        signature_doc.render_signature_doc(node.args), rets_source_text
    )

    if #node.body == 0 then
        local body_comments: {parser.Comment} = {}
        for _, comment in ipairs(node.body.comments or {}) do
            table.insert(body_comments, comment)
        end
        for _, comment in ipairs(node.body.end_comments or {}) do
            table.insert(body_comments, comment)
        end

        local comment_body = render_builders.build_comment_lines_doc(body_comments)
        return function_with_indent(name_prefix, sig_doc, doc.concat(comment_body))
    end

    local body_doc = render_block(node.body, body_layout)
    if body_doc == nil then
        return nil
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
        if not (layout is nil) then
            local if_block_layouts = layout.if_block_layouts
            if not (if_block_layouts is nil) then
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
                    return build_control_flow_head_doc("if", if_block.exp, " then")
                else
                    return build_control_flow_head_doc("elseif", if_block.exp, " then")
                end
            else
                return doc.text("else")
            end
        end

        if index > 1 then
            table.insert(parts, doc.line())
        end
        table.insert(parts, get_head_text())
        table.insert(
            parts,
            doc.indent(
                4,
                doc.concat(
                    {
                        doc.line(),
                        body_doc,
                    }
                )
            )
        )
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

    local body_doc = render_block(node.body, get_body_layout(layout))
    if body_doc == nil then
        return nil
    end

    local header = build_control_flow_head_doc("while", node.exp, " do")
    return block_with_close(header, body_doc, "end")
end

local function render_fornum_doc(
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    if node.var == nil
        or node.from == nil
        or node.to == nil
        or node.body == nil
        or #node.body == 0 then
        return nil
    end

    local body_doc = render_block(node.body, get_body_layout(layout))
    if body_doc == nil then
        return nil
    end

    local pre_header = doc.text("for " .. node.var.tk .. " = ")
    local header = doc.concat(
        {
            pre_header,
            build_exp_doc(node.from),
            doc.text(", "),
            build_exp_doc(node.to),
        }
    )
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

    local var_docs: {doc.Doc} = {}
    for _, var_node in ipairs(node.vars) do
        table.insert(var_docs, doc.text(var_node.tk))
    end

    local body_doc = render_block(node.body, get_body_layout(layout))
    if body_doc == nil then
        return nil
    end

    local header = doc.concat(
        {
            doc.text("for "),
            render_builders.build_comma_separated_docs(var_docs),
            doc.text(" in "),
            render_builders.build_mapped_comma_separated_docs(
                node.exps, build_exp_doc
            ),
            doc.text(" do"),
        }
    )
    return block_with_close(header, body_doc, "end")
end

local function render_repeat_doc(
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    if node.body == nil or node.exp == nil or #node.body == 0 then
        return nil
    end

    local body_doc = render_block(node.body, get_body_layout(layout))
    if body_doc is nil then
        return nil
    end

    return block_with_indent(
        doc.text("repeat"),
        body_doc,
        doc.concat({doc.text("until "), expr_doc.render_top_level_expr(node.exp)})
    )
end

local function render_do_doc(
    node: parser.Node, render_block: RenderBlock, layout: StatementLayout | nil
): doc.Doc | nil
    if node.body == nil or #node.body == 0 then
        return nil
    end

    local body_doc = render_block(node.body, get_body_layout(layout))
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
    elseif node.kind == "local_declaration" then
        return render_local_declaration_doc(node)
    elseif node.kind == "local_type" then
        return render_local_type_doc(node)
    elseif (node.kind == "local_function"
        or node.kind == "global_function"
        or node.kind == "record_function") then
        return render_function_definition_doc(node, render_block, layout)
    elseif node.kind == "if" then
        return render_if_doc(node, render_block, layout)
    elseif node.kind == "while" then
        return render_while_doc(node, render_block, layout)
    elseif node.kind == "fornum" then
        return render_fornum_doc(node, render_block, layout)
    elseif node.kind == "forin" then
        return render_forin_doc(node, render_block, layout)
    elseif node.kind == "repeat" then
        return render_repeat_doc(node, render_block, layout)
    elseif node.kind == "do" then
        return render_do_doc(node, render_block, layout)
    elseif node.kind == "break" then
        return doc.text("break")
    elseif node.kind == "op" then
        if end_line == node.y then
            return build_exp_doc(node)
        end
    end

    return nil
end

return stmt_doc
