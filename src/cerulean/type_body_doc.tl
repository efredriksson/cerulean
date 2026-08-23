-- A type declaration's body -> doc.Doc: record, interface and enum bodies, the
-- field entries inside them, and the type aliases that sit alongside. These are
-- definition-site constructs -- statement-shaped items with their own blank-line
-- and comment interplay -- as opposed to type_doc, which renders the type
-- expressions that appear at use sites.
local ast = require("cerulean.ast")
local construct_layout = require("cerulean.construct_layout")
local delimited_list_doc = require("cerulean.delimited_list_doc")
local doc = require("cerulean.doc")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local table_doc = require("cerulean.table_doc")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local type_body_doc = {}

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

function type_body_doc.macroexp_signature_doc(
    ctx: RenderContext, macroexp: ast.Node
): doc.Doc
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
function type_body_doc.macroexp_body_doc(
    ctx: RenderContext, macroexp: ast.Node
): doc.Doc
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
                type_body_doc.macroexp_signature_doc(ctx, macroexp),
            }
        )
    )
    local flat_body = doc.concat(
        {
            doc.indent_line(type_body_doc.macroexp_body_doc(ctx, macroexp)),
            doc.close("end"),
        }
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

function type_body_doc.render_type_doc(
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

return type_body_doc
