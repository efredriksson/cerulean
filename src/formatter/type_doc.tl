local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")

local render_return: function(parser.TupleType): doc.Doc

local function arg_name_doc(arg_name: string, is_optional: boolean): doc.Doc
    if arg_name ~= nil then
        local optional_str = is_optional and "?: " or ": "
        return doc.text(arg_name .. optional_str)
    else
        local optional_str = is_optional and "? " or ""
        return doc.text(optional_str)
    end
end

local function is_optional_arg(type_def: parser.FunctionType, index: integer): boolean
    local min_arity = type_def.min_arity or #type_def.args.tuple
    local is_variadic_tail = type_def.args.is_va

    return index > min_arity
        and not (is_variadic_tail and index == #type_def.args.tuple)
end

local function type_doc_render(type_def: parser.Type): doc.Doc
    if type_def is parser.NominalType then
        local parts: {doc.Doc} = {doc.text(table.concat(type_def.names, "."))}
        if type_def.typevals ~= nil and #type_def.typevals > 0 then
            table.insert(parts, doc.text("<"))
            for _, typeval in ipairs(type_def.typevals) do
                table.insert(parts, type_doc_render(typeval))
            end
            table.insert(parts, doc.text(">"))
        end
        return doc.concat(parts)
    elseif type_def is parser.ArrayType then
        return doc.concat(
            {
                doc.text("{"),
                type_doc_render(type_def.elements),
                doc.text("}"),
            }
        )
    elseif type_def is parser.TypeArgType then
        local typearg_text = doc.text(type_def.typearg)
        if type_def.constraint ~= nil then
            local constraint_text = type_doc_render(type_def.constraint)
            typearg_text = doc.concat({typearg_text, doc.text(" is "), constraint_text})
        end
        return typearg_text
    elseif type_def is parser.UnionType then
        local type_docs: {doc.Doc} = {}
        for _, t in ipairs(type_def.types) do
            table.insert(type_docs, type_doc_render(t))
        end
        return render_builders.build_separated_docs(type_docs, " | ")
    elseif type_def is parser.TupleType then
        local type_docs: {doc.Doc} = {}
        for _, t in ipairs(type_def.tuple) do
            table.insert(type_docs, type_doc_render(t))
        end
        return render_builders.build_separated_docs(type_docs, ", ")
    elseif type_def is parser.MapType then
        return doc.concat(
            {
                doc.text("{"),
                type_doc_render(type_def.keys),
                doc.text(": "),
                type_doc_render(type_def.values),
                doc.text("}"),
            }
        )
    elseif type_def is parser.TypeVarType then
        return doc.text(type_def.typevar)
    elseif type_def is parser.FunctionType then
        local arg_docs: {doc.Doc} = {}
        local argnames = type_def.args.argnames or {}
        for index, arg_type in ipairs(type_def.args.tuple) do
            local arg_name = arg_name_doc(
                argnames[index], is_optional_arg(type_def, index)
            )
            table.insert(arg_docs, doc.concat({arg_name, type_doc_render(arg_type)}))
        end
        local args_rendered = render_builders.build_separated_docs(arg_docs, ", ")
        local parts = {
            doc.text("function("),
            doc.indent(4, doc.concat({doc.softline(), args_rendered})),
            doc.close(")"),
            render_return(type_def.rets),
        }
        return doc.group(doc.concat(parts))
    elseif type_def is parser.TypeDeclType then
        assert(false, "implementation error, does not support enum/interface/...")
    elseif type_def is parser.TupleTableType then
        return doc.text(type_def.source_text)
    elseif parser.simple_types[type_def.typename] then
        return doc.text(type_def.typename)
    end

    assert(false, "unhandled type: " .. tostring(type_def.typename))
end

local type_doc = {}

function type_doc.render(type_def: parser.Type): doc.Doc
    local type_doc_res = type_doc_render(type_def)
    if type_def.paren then
        type_doc_res = doc.concat({doc.text("("), type_doc_res, doc.text(")")})
    end

    return type_doc_res
end

render_return = function(type_def: parser.TupleType): doc.Doc
    if type_def == nil or #type_def.tuple == 0 then
        return doc.text("")
    end
    return doc.concat({doc.text(": "), type_doc.render(type_def)})
end

function type_doc.render_return(type_def: parser.TupleType): doc.Doc
    return render_return(type_def)
end

return type_doc
