-- Single AST statement → doc.Doc. Returns nil for unsupported statement shapes.
local ast = require("cerulean.ast")
local construct_layout = require("cerulean.construct_layout")
local delimited_list_doc = require("cerulean.delimited_list_doc")
local doc = require("cerulean.doc")
local function_doc = require("cerulean.function_doc")
local inline_stmt_doc = require("cerulean.inline_stmt_doc")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local table_doc = require("cerulean.table_doc")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local stmt_doc = {}

-- A statement header's keyword/name tokens space-joined: the optional
-- `local`/`global` prefix followed by the rest (`type`/`record`/`function`, the
-- name). A nested type def (a record field) has no prefix, so `rest` stands alone.
local function header_text(keyword: string | nil, rest: {string}): doc.Doc
    local segments: {string} = {}
    if keyword ~= nil then
        table.insert(segments, keyword)
    end
    for _, part in ipairs(rest) do
        table.insert(segments, part)
    end
    return doc.text(table.concat(segments, " "))
end

local function render_type_alias_doc(
    ctx: RenderContext,
    name: string,
    typeargs: {ast.TypeArgType},
    def: ast.Type,
    type_keyword?: string,
    generic_doc?: doc.Doc
): doc.Doc
    return doc.concat(
        {
            header_text(type_keyword, {"type", name}),
            typeargs and type_doc.render_typeargs(ctx, typeargs) or doc.text(""),
            doc.text(" = "),
            type_doc.render(ctx, def, generic_doc),
        }
    )
end

local function render_enum_doc(
    ctx: RenderContext, stmt: ast.Node, def: ast.EnumType, keyword?: string
): doc.Doc
    local function build_header(): doc.Doc
        if stmt.is_type_declaration then
            return doc.concat(
                {header_text(keyword, {"type", def.declname}), doc.text(" = enum")}
            )
        end
        return header_text(keyword, {"enum", def.declname})
    end
    local header = build_header()

    local function render_enum_item(item_node: ast.Node): doc.Doc
        return doc.text(item_node.tk)
    end
    local function no_separator(_item: ast.Node, _is_last: boolean): doc.Doc
        return doc.text("")
    end
    -- force_wrap: an enum body is always one item per line, never flattened.
    local items_doc = delimited_list_doc.render_items(
        ctx,
        def.enum_items,
        ctx.slots:container_dangling_comments(def, #def.enum_items == 0),
        delimited_list_doc.ItemRenderSpec.new(
            true, render_enum_item, no_separator, true
        )
    )
    return construct_layout.block_with_close(header, items_doc, "end")
end

local render_type_def_doc: function(
    ctx: RenderContext,
    stmt_name: string,
    def: ast.Type,
    stmt: ast.Node,
    keyword?: string,
    generic_doc?: doc.Doc
): doc.Doc | nil

local function is_userdata_nominal(iface: ast.Type): boolean
    if not (iface is ast.NominalType) then
        return false
    end
    return #iface.names == 1 and iface.names[1] == "userdata"
end

local function has_string_key_field(record_def: ast.RecordLikeType): boolean
    for _, entry in ipairs(record_def.field_entries) do
        if entry.is_string_key then
            return true
        end
    end
    return false
end

-- When a record has a where clause and string-key body fields, rendering userdata
-- in the is-clause causes the second-pass parser to greedily consume the ["key"]
-- field as an index on the where expression, producing broken output. Moving
-- userdata into the body keeps the where expression boundary unambiguous.
local function needs_userdata_in_body(record_def: ast.RecordLikeType): boolean
    local has_where = record_def.meta_fields ~= nil
        and record_def.meta_fields["__is"] ~= nil
    return has_where and has_string_key_field(record_def)
end

local function render_interface_list_parts(
    ctx: RenderContext, record_def: ast.RecordLikeType
): {doc.Doc}
    local parts: {doc.Doc} = {}
    local filtered: {ast.Type} = {}
    for _, iface in ipairs(record_def.interface_list or {}) do
        if not is_userdata_nominal(iface) or not needs_userdata_in_body(record_def) then
            table.insert(filtered, iface)
        end
    end
    if #filtered == 0 then
        return parts
    end
    local iface_docs: {doc.Doc} = {}
    for _, iface in ipairs(filtered) do
        table.insert(iface_docs, type_doc.render(ctx, iface))
    end
    table.insert(parts, doc.text(" is "))
    table.insert(parts, render_builders.build_comma_separated_docs(iface_docs))
    return parts
end

local function macroexp_signature_doc(ctx: RenderContext, macroexp: ast.Node): doc.Doc
    local typeargs = macroexp.typeargs
        and type_doc.render_typeargs(ctx, macroexp.typeargs) or doc.text("")
    return doc.concat(
        {
            typeargs,
            type_doc.render_parameter_list(ctx, macroexp.args),
            doc.measure_flat(type_doc.render_return(ctx, macroexp.rets)),
        }
    )
end

-- Teal allows a macroexp body only one return expression.
local function macroexp_body_doc(ctx: RenderContext, macroexp: ast.Node): doc.Doc
    return doc.concat({doc.text("return "), ctx.render_expr(macroexp.exp)})
end

local function render_macroexp_field_doc(
    ctx: RenderContext, field_decl: doc.Doc, macroexp: ast.Node
): doc.Doc
    local header_group = doc.group_ref()
    local header = header_group:group(
        doc.concat(
            {
                field_decl,
                header_group:if_break(
                    doc.indent_line(doc.text("= ")), doc.text(" = ")
                ),
                doc.text("macroexp"),
                macroexp_signature_doc(ctx, macroexp),
            }
        )
    )
    local flat_body = doc.concat(
        {doc.indent_line(macroexp_body_doc(ctx, macroexp)), doc.close("end")}
    )
    return doc.concat({header, header_group:if_break(doc.indent(flat_body), flat_body)})
end

local function render_field_entry(
    ctx: RenderContext, entry: ast.FieldEntry
): doc.Doc | nil
    if entry.node ~= nil and entry.node.def ~= nil then
        return render_type_def_doc(ctx, entry.name, entry.node.def, entry.node, nil)
    end

    local function prefix(): string
        if entry.is_meta then
            return "metamethod "
        else
            return ""
        end
    end

    local function render_string_key(): string
        local key = render_builders.normalize_string_literal(
            entry.string_key_token, entry.is_longstring_key
        )
        local bracket_spacing = entry.is_longstring_key and " " or ""
        return "[" .. bracket_spacing .. key .. bracket_spacing .. "]"
    end

    local function field_name_prefix(): string
        if entry.is_string_key then
            return render_string_key() .. ": "
        end
        return prefix() .. entry.name .. ": "
    end

    local field_decl = doc.concat(
        {doc.text(field_name_prefix()), type_doc.render(ctx, entry.the_type)}
    )

    local field_type = entry.the_type
    if field_type is ast.GenericType then
        field_type = field_type.t
    end
    if not (field_type is ast.FunctionType) or field_type.macroexp == nil then
        return field_decl
    end

    local macroexp = field_type.macroexp
    assert(
        macroexp.args ~= nil and macroexp.rets ~= nil and macroexp.exp ~= nil,
        "bad record field macroexp"
    )
    return render_macroexp_field_doc(ctx, field_decl, macroexp)
end

local function render_record_like_body_doc(
    ctx: RenderContext, record_def: ast.RecordLikeType
): doc.Doc | nil
    local parts: {doc.Doc} = {}
    local line_before = false
    if needs_userdata_in_body(record_def) then
        for _, iface in ipairs(record_def.interface_list or {}) do
            if is_userdata_nominal(iface) then
                table.insert(parts, doc.text("userdata"))
                line_before = true
            end
        end
    end
    for index, entry in ipairs(record_def.field_entries) do
        line_before = render_builders.append_comment_docs(
            parts,
            ctx.slots:item_leading_comments(
                entry, record_def.field_entries[index - 1], index == 1
            ),
            line_before
        )
        table.insert(
            parts, render_builders.append_lines_pre_node(entry, line_before, doc.line())
        )
        table.insert(parts, render_field_entry(ctx, entry))

        table.insert(
            parts,
            render_builders.trailing_comment_doc(ctx.slots:trailing_comments(entry))
        )
        line_before = true
    end
    local end_comments = ctx.slots:container_dangling_comments(
        record_def, #record_def.field_entries == 0
    )
    render_builders.append_comment_docs(parts, end_comments, line_before)

    -- Hardline for the same reason with_indented_body uses one.
    return doc.concat({doc.indent_hardline(doc.concat(parts)), doc.close("end")})
end

local function render_record_like_header_doc(
    ctx: RenderContext, def: ast.RecordLikeType
): doc.Doc | nil
    local parts: {doc.Doc} = {}
    for _, part in ipairs(render_interface_list_parts(ctx, def)) do
        table.insert(parts, part)
    end
    if def.meta_fields ~= nil and def.meta_fields["__is"] ~= nil then
        local where_function = def.meta_fields["__is"]
        assert(where_function is ast.FunctionType)
        local where_macroexp = where_function.macroexp
        table.insert(parts, doc.text(" where "))
        local where_exp = where_macroexp.exp
        if where_exp.kind == "literal_table" then
            table.insert(parts, table_doc.build_table_doc(ctx, where_exp))
        else
            table.insert(parts, ctx.render_expr(where_exp))
        end
    end
    return doc.concat(parts)
end

local function render_record_like_doc(
    ctx: RenderContext,
    def: ast.RecordType | ast.InterfaceType,
    stmt: ast.Node,
    keyword?: string,
    generic_doc?: doc.Doc
): doc.Doc | nil
    local function build_header_parts(): {doc.Doc}
        if stmt.is_type_declaration then
            return {
                header_text(keyword, {"type", def.declname}),
                generic_doc or doc.text(""),
                doc.text(" = " .. def.typename),
            }
        else
            return {
                header_text(keyword, {def.typename, def.declname}),
                generic_doc or doc.text(""),
            }
        end
    end

    return doc.concat(
        {
            doc.concat(build_header_parts()),
            render_record_like_header_doc(ctx, def),
            render_record_like_body_doc(ctx, def),
        }
    )
end

render_type_def_doc = function(
    ctx: RenderContext,
    stmt_name: string,
    def: ast.Type,
    stmt: ast.Node,
    keyword?: string,
    generic_doc?: doc.Doc
): doc.Doc | nil
    if def is ast.EnumType then
        return render_enum_doc(ctx, stmt, def, keyword)
    elseif def is ast.GenericType then
        return render_type_def_doc(
            ctx,
            stmt_name,
            def.t,
            stmt,
            keyword,
            type_doc.render_typeargs(ctx, def.typeargs)
        )
    elseif def is ast.InterfaceType | ast.RecordType then
        return render_record_like_doc(ctx, def, stmt, keyword, generic_doc)
    else
        return render_type_alias_doc(
            ctx, stmt_name, stmt.typeargs, def, keyword, generic_doc
        )
    end
end

local function render_type_doc(
    ctx: RenderContext, stmt: ast.Node, keyword?: string
): doc.Doc | nil
    if stmt.value ~= nil and stmt.value.kind == "newtype" then
        return render_type_def_doc(ctx, stmt.var.tk, stmt.value.def, stmt, keyword)
    end
    local header = header_text(keyword, {"type", stmt.var.tk})
    if stmt.value == nil then
        return header
    end
    return doc.concat({header, doc.text(" = "), ctx.render_expr(stmt.value)})
end

local function render_function_name(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    local function render_function_owner(owner: ast.Node): string | nil
        if owner.kind == "name" then
            return owner.tk
        elseif owner.kind == "field" and owner.e1 ~= nil and owner.e2 ~= nil then
            local left = render_function_owner(owner.e1)
            if left == nil then
                return nil
            end
            return left .. "." .. owner.e2.tk
        end

        return nil
    end

    local function render_function_typeargs(fn_node: ast.Node): doc.Doc
        if fn_node.typeargs == nil then
            return doc.text("")
        end
        return type_doc.render_typeargs(ctx, fn_node.typeargs)
    end

    if node.name == nil then
        return nil
    end

    if node.kind == "local_macro" then
        return doc.concat(
            {
                doc.text("local macro " .. node.name.tk .. "!"),
                render_function_typeargs(node),
            }
        )
    end

    if node.fn_owner ~= nil then
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
    elseif node.is_local then
        return doc.concat(
            {
                doc.text("local function " .. node.name.tk),
                render_function_typeargs(node),
            }
        )
    end

    local function global_header(): string
        if node.implicit_global_function then
            return "function " .. node.name.tk
        end
        return "global function " .. node.name.tk
    end
    return doc.concat({doc.text(global_header()), render_function_typeargs(node)})
end

local function render_function_definition_doc(
    ctx: RenderContext, node: ast.Node
): doc.Doc | nil
    local name_prefix = render_function_name(ctx, node)
    if name_prefix is nil then
        return nil
    end
    return function_doc.render(ctx, node, name_prefix)
end

local function render_local_macroexp_doc(ctx: RenderContext, node: ast.Node): doc.Doc
    assert(
        node.name ~= nil and node.macrodef ~= nil and node.macrodef.exp ~= nil,
        "bad local_macroexp node"
    )
    local header = doc.group(
        doc.concat(
            {
                doc.text("local macroexp " .. node.name.tk),
                macroexp_signature_doc(ctx, node.macrodef),
            }
        )
    )
    return doc.concat(
        {
            header,
            doc.indent_line(macroexp_body_doc(ctx, node.macrodef)),
            doc.close("end"),
        }
    )
end

local function render_if_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
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
            if construct_layout.should_wrap_condition(ctx, if_block, if_block.exp) then
                return construct_layout.wrap_keyword_around(
                    doc.text(keyword),
                    ctx.render_expr(if_block.exp, true),
                    doc.text("then")
                )
            end
            local with_comment = render_builders.with_leading_inline_trivia(
                ctx.slots:opener_comments(if_block, "after_opener"),
                doc.text(keyword .. " "),
                ctx.render_expr(if_block.exp)
            )
            return doc.group(doc.concat({with_comment, doc.text(" then")}))
        end

        if index > 1 then
            table.insert(parts, doc.line())
        end
        table.insert(parts, get_head_text())
        table.insert(
            parts,
            render_builders.head_trivia_doc(ctx.slots:opener_comments(if_block, "head"))
        )
        table.insert(parts, doc.indent_line(body_doc))
    end

    table.insert(parts, doc.close("end"))
    return doc.concat(parts)
end

local function render_while_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    if node.exp == nil or node.body == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc == nil then
        return nil
    end

    local should_wrap_around = construct_layout.should_wrap_condition(
        ctx, node, node.exp
    )

    local function build_head_group(): doc.Doc
        if should_wrap_around then
            return construct_layout.wrap_keyword_around(
                doc.text("while"), ctx.render_expr(node.exp, true), doc.text("do")
            )
        end
        local while_and_exp_doc = render_builders.with_leading_inline_trivia(
            ctx.slots:opener_comments(node, "after_opener"),
            doc.text("while "),
            ctx.render_expr(node.exp)
        )
        return doc.group(doc.concat({while_and_exp_doc, doc.text(" do")}))
    end

    local header = doc.concat(
        {
            build_head_group(),
            render_builders.head_trivia_doc(ctx.slots:opener_comments(node, "head")),
        }
    )
    return construct_layout.block_with_close(header, body_doc, "end")
end

local function build_fornum_range_doc(node: ast.Node, ctx: RenderContext): doc.Doc
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

local function render_fornum_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
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
            render_builders.head_trivia_doc(ctx.slots:opener_comments(node, "head")),
        }
    )
    return construct_layout.block_with_close(
        render_builders.with_leading_inline_trivia(
            ctx.slots:opener_comments(node, "after_opener"),
            doc.text("for " .. node.var.tk .. " = "),
            tail
        ),
        body_doc,
        "end"
    )
end

local function render_forin_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
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

    -- A comment-free multi-expression list always wraps around the keywords (its
    -- commas need the hanging indent); a single expression only when it is a bare
    -- binary chain.
    local single_exp_wraps = #node.exps == 1
        and construct_layout.should_wrap_condition(ctx, node, node.exps[1])
    local multi_exp_wraps = #node.exps > 1
        and #ctx.slots:opener_comments(node, "after_opener") == 0
    local should_wrap_around = single_exp_wraps or multi_exp_wraps

    local for_in_keyword = doc.concat(
        {
            doc.text("for "),
            render_builders.build_comma_separated_docs(var_docs),
            doc.text(" in"),
        }
    )

    local function build_wrapped_exps(): doc.Doc
        if #node.exps == 1 then
            return ctx.render_expr(node.exps[1], true)
        end
        return render_builders.build_mapped_comma_separated_docs(ctx, node.exps)
    end

    local function build_header(): doc.Doc
        if should_wrap_around then
            return doc.concat(
                {
                    construct_layout.wrap_keyword_around(
                        for_in_keyword, build_wrapped_exps(), doc.text("do")
                    ),
                    render_builders.head_trivia_doc(
                        ctx.slots:opener_comments(node, "head")
                    ),
                }
            )
        end
        local tail_doc = doc.concat(
            {
                doc.text(" do"),
                render_builders.head_trivia_doc(
                    ctx.slots:opener_comments(node, "head")
                ),
            }
        )
        local exps_and_tail = doc.concat(
            {
                render_builders.build_mapped_comma_separated_docs(ctx, node.exps),
                tail_doc,
            }
        )
        return render_builders.with_leading_inline_trivia(
            ctx.slots:opener_comments(node, "after_opener"),
            doc.concat({for_in_keyword, doc.text(" ")}),
            exps_and_tail
        )
    end

    return construct_layout.block_with_close(build_header(), body_doc, "end")
end

local function render_repeat_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    if node.body == nil or node.exp == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc is nil then
        return nil
    end

    local header = doc.concat(
        {
            doc.text("repeat"),
            render_builders.head_trivia_doc(ctx.slots:opener_comments(node, "head")),
        }
    )

    -- block_with_indent always emits a newline into the body, which produces a
    -- spurious blank line when the body is empty. Skip it in that case.
    local is_empty_body = #node.body == 0
        and #ctx.slots:dangling_comments(node.body) == 0
    local should_wrap_around = construct_layout.should_wrap_condition(
        ctx, node, node.exp
    )

    local function build_until_doc(): doc.Doc
        if should_wrap_around then
            return construct_layout.wrap_keyword_before(
                doc.text("until"), ctx.render_expr(node.exp, true)
            )
        end
        return render_builders.with_leading_inline_trivia(
            ctx.slots:opener_comments(node, "after_opener"),
            doc.text("until "),
            ctx.render_expr(node.exp)
        )
    end

    local until_doc = build_until_doc()
    if is_empty_body then
        return doc.concat({header, doc.line(), until_doc})
    end
    return construct_layout.block_with_indent(header, body_doc, until_doc)
end

local function render_do_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    if node.body == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc == nil then
        return nil
    end

    return construct_layout.block_with_close(doc.text("do"), body_doc, "end")
end

function stmt_doc.render_statement_doc(
    ctx: RenderContext, node: ast.Node
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
    elseif node.kind == "bare_type" then
        return render_type_doc(ctx, node)
    elseif node.kind == "function_declaration" or node.kind == "local_macro" then
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
    elseif node.kind == "call" then
        return ctx.render_expr(node, true)
    elseif node.kind == "pragma" then
        return doc.text("--#pragma " .. node.pkey .. " " .. node.pvalue)
    end

    return nil
end

return stmt_doc
