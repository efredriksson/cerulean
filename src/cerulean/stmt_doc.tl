-- Single AST statement → doc.Doc. Returns nil for unsupported statement shapes.
local doc = require("cerulean.doc")
local expr_doc = require("cerulean.expr_doc")
local function_doc = require("cerulean.function_doc")
local inline_stmt_doc = require("cerulean.inline_stmt_doc")
local parser = require("cerulean.parser")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local signature_doc = require("cerulean.signature_doc")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local stmt_doc = {}

local function resolve_prefix(keyword?: string): string
    if keyword then
        return keyword .. " "
    end
    return ""
end

local function render_type_alias_doc(
    name: string,
    typeargs: {parser.TypeArgType},
    def: parser.Type,
    type_keyword?: string,
    generic_doc?: doc.Doc
): doc.Doc
    local declaration = resolve_prefix(type_keyword) .. "type " .. name
    return doc.concat(
        {
            doc.text(declaration),
            typeargs and type_doc.render_typeargs(typeargs) or doc.text(""),
            doc.text(" = "),
            type_doc.render(def, generic_doc),
        }
    )
end

local function with_indented_body(
    header: doc.Doc, body: doc.Doc, tail: doc.Doc
): doc.Doc
    return doc.concat({header, doc.indent_line(body), tail})
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

local function render_enum_doc(
    stmt: parser.Node, def: parser.EnumType, keyword?: string
): doc.Doc
    local function build_header(): doc.Doc
        local kw = resolve_prefix(keyword)
        if stmt.is_type_declaration then
            return doc.text(kw .. "type " .. def.declname .. " = enum")
        else
            return doc.text(kw .. "enum " .. def.declname)
        end
    end
    local header = build_header()

    local parts: {doc.Doc} = {}
    local line_before = false
    for _, item_node in ipairs(def.enum_items) do
        line_before = render_builders.append_comment_docs(
            parts, item_node.comments or {}, line_before
        )
        table.insert(
            parts, render_builders.append_lines_pre_node(item_node, line_before)
        )
        table.insert(parts, doc.text(item_node.tk))
        table.insert(parts, render_builders.trailing_comment_doc(item_node))
        line_before = true
    end
    local end_comments = def.end_comments or stmt.end_comments or {}
    render_builders.append_comment_docs(parts, end_comments, line_before)

    return block_with_close(header, doc.concat(parts), "end")
end

local render_type_def_doc: function(
    ctx: RenderContext,
    stmt_name: string,
    def: parser.Type,
    stmt: parser.Node,
    keyword: string,
    generic_doc?: doc.Doc
): doc.Doc | nil

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

local function render_field_entry(
    ctx: RenderContext, entry: parser.FieldEntry
): doc.Doc | nil
    if entry.node ~= nil and entry.node.newtype ~= nil then
        return render_type_def_doc(
            ctx, entry.name, entry.node.newtype.def, entry.node, nil
        )
    end

    local function prefix(): string
        if entry.is_meta then
            return "metamethod "
        else
            return ""
        end
    end

    return doc.concat(
        {doc.text(prefix() .. entry.name .. ": "), type_doc.render(entry.the_type)}
    )
end

local function render_record_like_body_doc(
    ctx: RenderContext, node: parser.Node, record_def: parser.RecordLikeType
): doc.Doc | nil
    local parts: {doc.Doc} = {}
    local line_before = false
    for _, entry in ipairs(record_def.field_entries) do
        line_before = render_builders.append_comment_docs(
            parts, entry.comments or {}, line_before
        )
        table.insert(parts, render_builders.append_lines_pre_node(entry, line_before))
        table.insert(parts, render_field_entry(ctx, entry))

        if entry.trailing_comment then
            table.insert(parts, doc.text(" " .. entry.trailing_comment.text))
        end
        line_before = true
    end
    render_builders.append_comment_docs(parts, node.end_comments or {}, line_before)

    return doc.concat(
        {
            doc.indent_line(doc.concat(parts)),
            doc.close("end"),
        }
    )
end

local function render_record_like_header_doc(
    ctx: RenderContext, def: parser.RecordLikeType
): doc.Doc | nil
    local parts: {doc.Doc} = {}
    for _, part in ipairs(render_interface_list_parts(def)) do
        table.insert(parts, part)
    end
    if def.meta_fields ~= nil and def.meta_fields["__is"] ~= nil then
        local where_function = def.meta_fields["__is"]
        assert(where_function is parser.FunctionType)
        local where_macroexp = where_function.macroexp
        table.insert(parts, doc.text(" where "))
        table.insert(parts, ctx.render_expr(where_macroexp.exp))
    end
    return doc.concat(parts)
end

local function render_record_like_doc(
    ctx: RenderContext,
    def: parser.RecordType | parser.InterfaceType,
    stmt: parser.Node,
    keyword?: string,
    generic_doc?: doc.Doc
): doc.Doc | nil
    local function build_header_parts(): {doc.Doc}
        if stmt.is_type_declaration then
            return {
                doc.text(resolve_prefix(keyword) .. "type" .. " " .. def.declname),
                generic_doc or doc.text(""),
                doc.text(" = " .. def.typename),
            }
        else
            return {
                doc.text(
                    resolve_prefix(keyword) .. def.typename .. " " .. def.declname
                ),
                generic_doc or doc.text(""),
            }
        end
    end

    return doc.concat(
        {
            doc.concat(build_header_parts()),
            render_record_like_header_doc(ctx, def),
            render_record_like_body_doc(ctx, stmt, def),
        }
    )
end

render_type_def_doc = function(
    ctx: RenderContext,
    stmt_name: string,
    def: parser.Type,
    stmt: parser.Node,
    keyword: string,
    generic_doc?: doc.Doc
): doc.Doc | nil
    if def is parser.EnumType then
        return render_enum_doc(stmt, def, keyword)
    elseif def is parser.GenericType then
        return render_type_def_doc(
            ctx, stmt_name, def.t, stmt, keyword, type_doc.render_typeargs(def.typeargs)
        )
    elseif def is parser.InterfaceType | parser.RecordType then
        return render_record_like_doc(ctx, def, stmt, keyword, generic_doc)
    else
        return render_type_alias_doc(
            stmt_name, stmt.typeargs, def, keyword, generic_doc
        )
    end
end

local function render_type_doc(
    ctx: RenderContext, stmt: parser.Node, keyword: string
): doc.Doc | nil
    if stmt.value.kind ~= "newtype" then
        return doc.concat(
            {
                doc.text(keyword .. " type " .. stmt.var.tk .. " = "),
                ctx.render_expr(stmt.value),
            }
        )
    end

    return render_type_def_doc(ctx, stmt.var.tk, stmt.value.newtype.def, stmt, keyword)
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
        return type_doc.render_typeargs(fn_node.typeargs)
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
        local prefix = node.implicit_global_function and "function "
            or "global function "
        return doc.concat(
            {doc.text(prefix .. node.name.tk), render_function_typeargs(node)}
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
    ctx: RenderContext, node: parser.Node
): doc.Doc | nil
    local name_prefix = render_function_name(node)
    if name_prefix is nil then
        return nil
    end
    return function_doc.render(ctx, node, name_prefix)
end

local function render_local_macroexp_doc(ctx: RenderContext, node: parser.Node): doc.Doc
    assert(
        node.name ~= nil and node.macrodef ~= nil and node.macrodef.exp ~= nil,
        "bad local_macroexp node"
    )
    local header = doc.group(
        doc.concat(
            {
                doc.text("local macroexp " .. node.name.tk),
                signature_doc.render_signature_doc(node.macrodef.args),
                type_doc.render_return(node.macrodef.rets),
            }
        )
    )
    local body_doc = doc.concat(
        {doc.text("return "), ctx.render_expr(node.macrodef.exp)}
    )
    return doc.concat(
        {
            header,
            doc.indent_line(body_doc),
            doc.close("end"),
        }
    )
end

local function render_if_doc(ctx: RenderContext, node: parser.Node): doc.Doc | nil
    if node.if_blocks == nil then
        return nil
    end

    local parts: {doc.Doc} = {doc.break_parent()}
    for index, if_block in ipairs(node.if_blocks) do
        if if_block.body == nil then
            return nil
        end
        local body_doc = ctx.render_block(if_block.body)
        if body_doc == nil then
            return nil
        end

        local function get_head_text(): doc.Doc
            if if_block.exp == nil then
                return doc.text("else")
            end
            local keyword = index == 1 and "if" or "elseif"
            local with_comment = render_builders.with_leading_inline_comment(
                if_block, doc.text(keyword .. " "), expr_doc.render(ctx, if_block.exp)
            )
            return doc.group(doc.concat({with_comment, doc.text(" then")}))
        end

        if index > 1 then
            table.insert(parts, doc.line())
        end
        table.insert(parts, get_head_text())
        table.insert(parts, render_builders.trailing_comment_doc(if_block))
        table.insert(parts, doc.indent_line(body_doc))
    end

    table.insert(parts, doc.close("end"))
    return doc.concat(parts)
end

local function render_while_doc(ctx: RenderContext, node: parser.Node): doc.Doc | nil
    if node.exp == nil or node.body == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc == nil then
        return nil
    end

    local while_and_exp_doc = render_builders.with_leading_inline_comment(
        node, doc.text("while "), expr_doc.render(ctx, node.exp)
    )
    local header = doc.concat(
        {
            doc.group(doc.concat({while_and_exp_doc, doc.text(" do")})),
            render_builders.head_trailing_comment_doc(node),
        }
    )
    return block_with_close(header, body_doc, "end")
end

local function build_fornum_range_doc(node: parser.Node, ctx: RenderContext): doc.Doc
    local range_parts: {doc.Doc} = {
        ctx.render_expr(node.from),
        doc.text(", "),
        ctx.render_expr(node.to),
    }
    if node.step ~= nil then
        table.insert(range_parts, doc.text(", "))
        table.insert(range_parts, ctx.render_expr(node.step))
    end
    return doc.concat(range_parts)
end

local function render_fornum_doc(ctx: RenderContext, node: parser.Node): doc.Doc | nil
    if node.var == nil or node.from == nil or node.to == nil or node.body == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc == nil then
        return nil
    end

    local tail = doc.concat(
        {
            build_fornum_range_doc(node, ctx),
            doc.text(" do"),
            render_builders.head_trailing_comment_doc(node),
        }
    )
    return block_with_close(
        render_builders.with_leading_inline_comment(
            node, doc.text("for " .. node.var.tk .. " = "), tail
        ),
        body_doc,
        "end"
    )
end

local function render_forin_doc(ctx: RenderContext, node: parser.Node): doc.Doc | nil
    if node.vars == nil or node.exps == nil or node.body == nil then
        return nil
    end

    local var_docs: {doc.Doc} = {}
    for _, var_node in ipairs(node.vars) do
        table.insert(var_docs, doc.text(var_node.tk))
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc == nil then
        return nil
    end

    local exps_doc = render_builders.build_mapped_comma_separated_docs(
        node.exps, ctx.render_expr
    )
    local tail_doc = doc.concat(
        {doc.text(" do"), render_builders.head_trailing_comment_doc(node)}
    )
    local for_in_doc = doc.concat(
        {
            doc.text("for "),
            render_builders.build_comma_separated_docs(var_docs),
            doc.text(" in "),
        }
    )
    local header = render_builders.with_leading_inline_comment(
        node, for_in_doc, doc.concat({exps_doc, tail_doc})
    )
    return block_with_close(header, body_doc, "end")
end

local function render_repeat_doc(ctx: RenderContext, node: parser.Node): doc.Doc | nil
    if node.body == nil or node.exp == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc is nil then
        return nil
    end

    local header = doc.concat(
        {doc.text("repeat"), render_builders.head_trailing_comment_doc(node)}
    )

    -- block_with_indent always emits a newline into the body, which produces a
    -- spurious blank line when the body is empty. Skip it in that case.
    local is_empty_body = #node.body == 0 and #(node.body.end_comments or {}) == 0
    local until_doc = render_builders.with_leading_inline_comment(
        node, doc.text("until "), expr_doc.render(ctx, node.exp)
    )
    if is_empty_body then
        return doc.concat({header, doc.line(), until_doc})
    end
    return block_with_indent(header, body_doc, until_doc)
end

local function render_do_doc(ctx: RenderContext, node: parser.Node): doc.Doc | nil
    if node.body == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc == nil then
        return nil
    end

    return block_with_close(doc.text("do"), body_doc, "end")
end

function stmt_doc.render_statement_doc(
    ctx: RenderContext, node: parser.Node
): doc.Doc | nil
    if node.kind == "return" then
        return inline_stmt_doc.render_return_doc(ctx, node)
    elseif node.kind == "assignment" then
        return inline_stmt_doc.render_assignment_doc(ctx, node)
    elseif node.kind == "local_declaration" then
        return inline_stmt_doc.render_declaration_doc(ctx, node, "local")
    elseif node.kind == "global_declaration" then
        return inline_stmt_doc.render_declaration_doc(ctx, node, "global")
    elseif node.kind == "local_type" then
        return render_type_doc(ctx, node, "local")
    elseif node.kind == "global_type" then
        return render_type_doc(ctx, node, "global")
    elseif (node.kind == "local_function"
        or node.kind == "global_function"
        or node.kind == "record_function") then
        return render_function_definition_doc(ctx, node)
    elseif node.kind == "local_macroexp" then
        return render_local_macroexp_doc(ctx, node)
    elseif node.kind == "if" then
        return render_if_doc(ctx, node)
    elseif node.kind == "while" then
        return render_while_doc(ctx, node)
    elseif node.kind == "fornum" then
        return render_fornum_doc(ctx, node)
    elseif node.kind == "forin" then
        return render_forin_doc(ctx, node)
    elseif node.kind == "repeat" then
        return render_repeat_doc(ctx, node)
    elseif node.kind == "do" then
        return render_do_doc(ctx, node)
    elseif node.kind == "break" then
        return doc.text("break")
    elseif node.kind == "goto" then
        return doc.text("goto " .. node.label)
    elseif node.kind == "label" then
        return doc.text("::" .. node.label .. "::")
    elseif node.kind == "op" then
        return ctx.render_expr(node)
    end

    return nil
end

return stmt_doc
