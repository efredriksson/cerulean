-- Single AST statement → doc.Doc. Returns nil for unsupported statement shapes.
local doc = require("formatter.doc")
local expr_doc = require("formatter.expr_doc")
local function_doc = require("formatter.function_doc")
local inline_stmt_doc = require("formatter.inline_stmt_doc")
local layout_types = require("formatter.layout_types")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local render_context = require("formatter.render_context")
local type_doc = require("formatter.type_doc")

local type BlockLayout = layout_types.BlockLayout
local type StatementLayout = layout_types.StatementLayout
local type RenderContext = render_context.RenderContext

local stmt_doc = {}

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function get_body_layout(layout: StatementLayout | nil): BlockLayout | nil
    if layout is nil then
        return nil
    end
    return layout.body_layout
end

local function render_typearg_list(typeargs: {parser.TypeArgType}): doc.Doc
    if #typeargs == 0 then
        return doc.text("")
    end

    local parts: {doc.Doc} = {}
    for _, typearg in ipairs(typeargs) do
        table.insert(parts, type_doc.render(typearg))
    end
    return doc.concat(
        {
            doc.text("<"),
            render_builders.build_comma_separated_docs(parts),
            doc.text(">"),
        }
    )
end

local function with_indented_body(
    header: doc.Doc, body: doc.Doc, tail: doc.Doc
): doc.Doc
    return doc.concat({header, doc.indent(4, doc.concat({doc.line(), body})), tail})
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

local function build_control_flow_head_doc(
    ctx: RenderContext, head_keyword: string, exp: parser.Node, tail_text: string
): doc.Doc
    return doc.group(
        doc.concat(
            {
                doc.text(head_keyword .. " "),
                expr_doc.render(ctx, exp),
                doc.text(tail_text),
            }
        )
    )
end

local function render_return_doc(ctx: RenderContext, stmt: parser.Node): doc.Doc
    return inline_stmt_doc.render_return_doc(ctx, stmt)
end

local function render_assignment_doc(ctx: RenderContext, stmt: parser.Node): doc.Doc
    return inline_stmt_doc.render_assignment_doc(ctx, stmt)
end

local function render_local_declaration_doc(
    ctx: RenderContext, stmt: parser.Node
): doc.Doc | nil
    return inline_stmt_doc.render_local_declaration_doc(ctx, stmt)
end

local function render_enum_doc(
    stmt: parser.Node, def: parser.EnumType, nested?: boolean
): doc.Doc
    local header: doc.Doc
    if nested then
        header = doc.text("enum " .. def.declname)
    elseif stmt.is_type_declaration then
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

local render_nested_typedecl_doc: function(RenderContext, parser.Node): doc.Doc | nil

local record ResolvedRecordLikeDef
    keyword: string
    record_def: parser.RecordLikeType
    typeargs_str: doc.Doc
    new: function(string, parser.RecordLikeType, doc.Doc): ResolvedRecordLikeDef
end

function ResolvedRecordLikeDef.new(
    keyword: string, record_def: parser.RecordLikeType, typeargs_str: doc.Doc
): ResolvedRecordLikeDef
    local self = setmetatable(
        {}, {__index = ResolvedRecordLikeDef}
    ) as ResolvedRecordLikeDef
    self.keyword = keyword
    self.record_def = record_def
    self.typeargs_str = typeargs_str
    return self
end

local function resolve_record_like_def(
    def: parser.FirstClassType
): ResolvedRecordLikeDef | nil
    local typeargs_str = doc.text("")
    if def is parser.GenericType then
        typeargs_str = render_typearg_list(def.typeargs or {})
        def = def.t
        if def == nil then
            return nil
        end
    end
    if def is parser.InterfaceType then
        return ResolvedRecordLikeDef.new("interface", def, typeargs_str)
    elseif def is parser.RecordType then
        return ResolvedRecordLikeDef.new("record", def, typeargs_str)
    end
    return nil
end

local function render_interface_list_parts(record_def: parser.RecordLikeType): {doc.Doc}
    local parts: {doc.Doc} = {}
    if record_def.interface_list == nil or #record_def.interface_list == 0 then
        return parts
    end
    table.insert(parts, doc.text(" is "))
    for index, iface in ipairs(record_def.interface_list) do
        table.insert(parts, type_doc.render(iface))
        if index < #record_def.interface_list then
            table.insert(parts, doc.text(", "))
        end
    end
    return parts
end

local function render_record_like_body_doc(
    ctx: RenderContext,
    node: parser.Node,
    header_parts: {doc.Doc},
    record_def: parser.RecordLikeType
): doc.Doc | nil
    local record_items = render_builders.CommentLineItems.new()
    for _, field_name in ipairs(record_def.field_order) do
        local field_type = record_def.fields[field_name]
        if field_type == nil or field_type.source_text == nil then
            local nested_node = record_def.nodes[field_name]
            if nested_node == nil or nested_node.newtype == nil then
                return nil
            end
            record_items:add(
                render_nested_typedecl_doc(ctx, nested_node), nested_node.y, {}, false
            )
        else
            local field_comments = ((record_def.field_comments or {})[field_name]
                or {}) as {{parser.Comment}}
            local parser_comments: {parser.Comment} = {}
            for _, overload_comments in ipairs(field_comments) do
                for _, comment in ipairs(overload_comments) do
                    table.insert(parser_comments, comment)
                end
            end
            record_items:add(
                doc.text(field_name .. ": " .. field_type.source_text),
                render_builders.node_end_line(field_type as parser.Node),
                parser_comments,
                false
            )
        end
    end
    for _, meta_name in ipairs(record_def.meta_field_order or {}) do
        if meta_name ~= "__is" then
            local meta_type = record_def.meta_fields[meta_name]
            local meta_comments = ((record_def.meta_field_comments or {})[meta_name]
                or {}) as {{parser.Comment}}
            local parser_comments: {parser.Comment} = {}
            for _, overload_comments in ipairs(meta_comments) do
                for _, comment in ipairs(overload_comments) do
                    table.insert(parser_comments, comment)
                end
            end
            record_items:add(
                doc.concat(
                    {
                        doc.text("metamethod " .. meta_name .. ": "),
                        type_doc.render(meta_type),
                    }
                ),
                render_builders.node_end_line(meta_type as parser.Node),
                parser_comments,
                false
            )
        end
    end
    record_items:add_end_comments(node.end_comments or {})
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

local function render_resolved_record_doc(
    ctx: RenderContext,
    node: parser.Node,
    header_parts: {doc.Doc},
    resolved: ResolvedRecordLikeDef
): doc.Doc | nil
    for _, part in ipairs(render_interface_list_parts(resolved.record_def)) do
        table.insert(header_parts, part)
    end
    if resolved.keyword == "interface"
        and resolved.record_def.meta_fields ~= nil
        and resolved.record_def.meta_fields["__is"] ~= nil then
        local where_function = resolved.record_def.meta_fields["__is"]
        if not (where_function is parser.FunctionType) then
            return nil
        end
        if where_function.macroexp == nil then
            return nil
        end
        local where_macroexp = where_function.macroexp as parser.Node
        if where_macroexp.exp == nil then
            return nil
        end
        table.insert(header_parts, doc.text(" where "))
        table.insert(header_parts, ctx.render_expr(where_macroexp.exp))
    end
    return render_record_like_body_doc(ctx, node, header_parts, resolved.record_def)
end

local function render_local_record_doc(
    ctx: RenderContext, stmt: parser.Node
): doc.Doc | nil
    if stmt.value == nil or stmt.value.newtype == nil then
        return nil
    end
    local def = stmt.value.newtype.def
    if def is parser.EnumType then
        return render_enum_doc(stmt, def)
    end
    local resolved = resolve_record_like_def(def)
    if not (resolved is ResolvedRecordLikeDef) then
        return nil
    end
    local header_parts: {doc.Doc}
    if stmt.is_type_declaration then
        header_parts = {
            doc.concat(
                {
                    doc.text("local type " .. stmt.var.tk),
                    resolved.typeargs_str,
                    doc.text(" = " .. resolved.keyword),
                }
            ),
        }
    else
        header_parts = {
            doc.concat(
                {
                    doc.text("local " .. resolved.keyword .. " " .. stmt.var.tk),
                    resolved.typeargs_str,
                }
            ),
        }
    end
    return render_resolved_record_doc(ctx, stmt, header_parts, resolved)
end

render_nested_typedecl_doc = function(
    ctx: RenderContext, nested_node: parser.Node
): doc.Doc | nil
    if nested_node.newtype == nil then
        return nil
    end
    local def = nested_node.newtype.def
    if def is parser.EnumType then
        return render_enum_doc(nested_node, def, true)
    end
    local resolved = resolve_record_like_def(def)
    if not (resolved is ResolvedRecordLikeDef) then
        return nil
    end
    local header_parts: {doc.Doc} = {
        doc.text(resolved.keyword .. " " .. resolved.record_def.declname),
        resolved.typeargs_str,
    }
    return render_resolved_record_doc(ctx, nested_node, header_parts, resolved)
end

local function render_local_type_doc(
    ctx: RenderContext, stmt: parser.Node
): doc.Doc | nil
    if stmt.var == nil or stmt.value == nil then
        return nil
    end
    if stmt.value.kind ~= "newtype" then
        return doc.concat(
            {
                doc.text("local type " .. stmt.var.tk .. " = "),
                ctx.render_expr(stmt.value),
            }
        )
    end
    if stmt.value.newtype == nil or stmt.value.newtype.def == nil then
        return nil
    end
    local def = stmt.value.newtype.def
    if def.typename == "record"
        or def.typename == "interface"
        or def.typename == "generic"
        or def.typename == "enum"
        or def.typename == "typedecl" then
        return render_local_record_doc(ctx, stmt)
    end
    return doc.concat(
        {doc.text("local type " .. stmt.var.tk .. " = "), type_doc.render(def)}
    )
end

local function render_function_name(node: parser.Node): doc.Doc | nil
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

    local function render_function_typeargs(fn_node: parser.Node): doc.Doc
        if fn_node.typeargs == nil then
            return doc.text("")
        end
        return render_typearg_list(fn_node.typeargs)
    end

    if node.kind == "local_function" and node.name ~= nil then
        return doc.concat(
            {
                doc.text("local function " .. node.name.tk),
                render_function_typeargs(node),
            }
        )
    elseif node.kind == "global_function"
        and node.name ~= nil
        and not node.is_method then
        return doc.concat(
            {doc.text("function " .. node.name.tk), render_function_typeargs(node)}
        )
    elseif node.kind == "record_function"
        and node.fn_owner ~= nil
        and node.name ~= nil then
        local owner = render_function_owner(node.fn_owner)
        if owner == nil then
            return nil
        end
        local separator = node.is_method and ":" or "."
        return doc.concat(
            {
                doc.text("function " .. owner .. separator .. node.name.tk),
                render_function_typeargs(node),
            }
        )
    end

    return nil
end

local function render_function_definition_doc(
    ctx: RenderContext, node: parser.Node, layout: StatementLayout | nil
): doc.Doc | nil
    local name_prefix = render_function_name(node)
    if name_prefix is nil then
        return nil
    end

    local body_layout: BlockLayout | nil = nil
    if not (layout is nil) then
        body_layout = layout.body_layout
    end

    return function_doc.render(ctx, node, name_prefix, body_layout)
end

local function render_if_doc(
    ctx: RenderContext, node: parser.Node, layout: StatementLayout | nil
): doc.Doc | nil
    if node.if_blocks == nil then
        return nil
    end

    local parts: {doc.Doc} = {doc.break_parent()}
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
        local body_doc = ctx.render_block(if_block.body, if_block_layout)
        if body_doc == nil then
            return nil
        end

        local function get_head_text(): doc.Doc
            if if_block.exp ~= nil then
                if index == 1 then
                    return build_control_flow_head_doc(ctx, "if", if_block.exp, " then")
                else
                    return build_control_flow_head_doc(
                        ctx, "elseif", if_block.exp, " then"
                    )
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
    ctx: RenderContext, node: parser.Node, layout: StatementLayout | nil
): doc.Doc | nil
    if node.exp == nil or node.body == nil or #node.body == 0 then
        return nil
    end

    local body_doc = ctx.render_block(node.body, get_body_layout(layout))
    if body_doc == nil then
        return nil
    end

    local header = build_control_flow_head_doc(ctx, "while", node.exp, " do")
    return block_with_close(header, body_doc, "end")
end

local function render_fornum_doc(
    ctx: RenderContext, node: parser.Node, layout: StatementLayout | nil
): doc.Doc | nil
    if node.var == nil
        or node.from == nil
        or node.to == nil
        or node.body == nil
        or #node.body == 0 then
        return nil
    end

    local body_doc = ctx.render_block(node.body, get_body_layout(layout))
    if body_doc == nil then
        return nil
    end

    local pre_header = doc.text("for " .. node.var.tk .. " = ")
    local header = doc.concat(
        {
            pre_header,
            ctx.render_expr(node.from),
            doc.text(", "),
            ctx.render_expr(node.to),
        }
    )
    if node.step ~= nil then
        header = doc.concat({header, doc.text(", "), ctx.render_expr(node.step)})
    end

    return block_with_close(doc.concat({header, doc.text(" do")}), body_doc, "end")
end

local function render_forin_doc(
    ctx: RenderContext, node: parser.Node, layout: StatementLayout | nil
): doc.Doc | nil
    if node.vars == nil or node.exps == nil or node.body == nil or #node.body == 0 then
        return nil
    end

    local var_docs: {doc.Doc} = {}
    for _, var_node in ipairs(node.vars) do
        table.insert(var_docs, doc.text(var_node.tk))
    end

    local body_doc = ctx.render_block(node.body, get_body_layout(layout))
    if body_doc == nil then
        return nil
    end

    local header = doc.concat(
        {
            doc.text("for "),
            render_builders.build_comma_separated_docs(var_docs),
            doc.text(" in "),
            render_builders.build_mapped_comma_separated_docs(
                node.exps, ctx.render_expr
            ),
            doc.text(" do"),
        }
    )
    return block_with_close(header, body_doc, "end")
end

local function render_repeat_doc(
    ctx: RenderContext, node: parser.Node, layout: StatementLayout | nil
): doc.Doc | nil
    if node.body == nil or node.exp == nil or #node.body == 0 then
        return nil
    end

    local body_doc = ctx.render_block(node.body, get_body_layout(layout))
    if body_doc is nil then
        return nil
    end

    return block_with_indent(
        doc.text("repeat"),
        body_doc,
        doc.concat({doc.text("until "), expr_doc.render(ctx, node.exp)})
    )
end

local function render_do_doc(
    ctx: RenderContext, node: parser.Node, layout: StatementLayout | nil
): doc.Doc | nil
    if node.body == nil or #node.body == 0 then
        return nil
    end

    local body_doc = ctx.render_block(node.body, get_body_layout(layout))
    if body_doc == nil then
        return nil
    end

    return block_with_close(doc.text("do"), body_doc, "end")
end

function stmt_doc.render_statement_doc(
    ctx: RenderContext, node: parser.Node, layout: StatementLayout | nil
): doc.Doc | nil
    local end_line = node_end_line(node)

    if node.kind == "return" and end_line == node.y then
        return render_return_doc(ctx, node)
    elseif node.kind == "assignment" and end_line == node.y then
        return render_assignment_doc(ctx, node)
    elseif node.kind == "local_declaration" then
        return render_local_declaration_doc(ctx, node)
    elseif node.kind == "local_type" then
        return render_local_type_doc(ctx, node)
    elseif (node.kind == "local_function"
        or node.kind == "global_function"
        or node.kind == "record_function") then
        return render_function_definition_doc(ctx, node, layout)
    elseif node.kind == "if" then
        return render_if_doc(ctx, node, layout)
    elseif node.kind == "while" then
        return render_while_doc(ctx, node, layout)
    elseif node.kind == "fornum" then
        return render_fornum_doc(ctx, node, layout)
    elseif node.kind == "forin" then
        return render_forin_doc(ctx, node, layout)
    elseif node.kind == "repeat" then
        return render_repeat_doc(ctx, node, layout)
    elseif node.kind == "do" then
        return render_do_doc(ctx, node, layout)
    elseif node.kind == "break" then
        return doc.text("break")
    elseif node.kind == "op" then
        if end_line == node.y then
            return ctx.render_expr(node)
        end
    end

    return nil
end

return stmt_doc
