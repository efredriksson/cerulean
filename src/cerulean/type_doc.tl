local doc = require("cerulean.doc")
local parser = require("cerulean.parser")
local render_builders = require("cerulean.render_builders")

local render_return: function(parser.TupleType): doc.Doc
local render_type: function(parser.Type): doc.Doc

local function arg_name_doc(
    arg_name: string, is_optional: boolean, is_variadic: boolean
): doc.Doc, doc.Doc
    local function type_suffix(): doc.Doc
        if is_variadic and arg_name ~= nil then
            return doc.text("...")
        else
            return doc.text("")
        end
    end

    if arg_name ~= nil then
        local optional_str = is_optional and "?: " or ": "
        return doc.text(arg_name .. optional_str), type_suffix()
    elseif is_variadic then
        return doc.text("...: "), type_suffix()
    else
        local optional_str = is_optional and "? " or ""
        return doc.text(optional_str), type_suffix()
    end
end

local function is_optional_arg(type_def: parser.FunctionType, index: integer): boolean
    local min_arity = type_def.min_arity or #type_def.args.tuple
    local is_variadic_tail = type_def.args.is_va

    return index > min_arity
        and not (is_variadic_tail and index == #type_def.args.tuple)
end

local type_doc = {}

local type_doc_render: function(type_def: parser.Type, generic_doc?: doc.Doc): doc.Doc

function type_doc.render_typeargs(typeargs: {parser.TypeArgType}): doc.Doc
    local typearg_docs: {doc.Doc} = {}
    for _, typearg in ipairs(typeargs) do
        table.insert(typearg_docs, render_type(typearg))
    end
    return doc.concat(
        {
            doc.text("<"),
            render_builders.build_separated_docs(typearg_docs, ", "),
            doc.text(">"),
        }
    )
end

local function function_type_render(
    type_def: parser.FunctionType, generic_doc?: doc.Doc
): doc.Doc
    local arg_docs: {doc.Doc} = {}
    local argnames = type_def.args.argnames or {}
    for index, arg_type in ipairs(type_def.args.tuple) do
        local is_variadic = type_def.args.is_va and index == #type_def.args.tuple
        local arg_name, type_suffix = arg_name_doc(
            argnames[index], is_optional_arg(type_def, index), is_variadic
        )
        local rendered_type = render_type(arg_type)
        table.insert(arg_docs, doc.concat({arg_name, rendered_type, type_suffix}))
    end
    local opts = render_builders.DelimitedSequenceOptions.new("(", ")")
    return doc.concat(
        {
            doc.text("function"),
            generic_doc or doc.text(""),
            render_builders.build_delimited_sequence_doc(arg_docs, opts),
            render_return(type_def.rets),
        }
    )
end

type_doc_render = function(type_def: parser.Type, generic_doc?: doc.Doc): doc.Doc
    if type_def is parser.NominalType then
        local parts: {doc.Doc} = {doc.text(table.concat(type_def.names, "."))}
        if type_def.typevals ~= nil and #type_def.typevals > 0 then
            local typeval_docs: {doc.Doc} = {}
            for _, typeval in ipairs(type_def.typevals) do
                table.insert(typeval_docs, render_type(typeval))
            end
            table.insert(parts, doc.text("<"))
            table.insert(
                parts, render_builders.build_separated_docs(typeval_docs, ", ")
            )
            table.insert(parts, doc.text(">"))
        end
        return doc.concat(parts)
    elseif type_def is parser.ArrayType then
        return doc.concat(
            {
                doc.text("{"),
                render_type(type_def.elements),
                doc.text("}"),
            }
        )
    elseif type_def is parser.TypeArgType then
        local typearg_text = doc.text(type_def.typearg)
        if type_def.constraint ~= nil then
            local constraint_text = render_type(type_def.constraint)
            typearg_text = doc.concat({typearg_text, doc.text(" is "), constraint_text})
        end
        return typearg_text
    elseif type_def is parser.UnionType then
        local type_docs: {doc.Doc} = {}
        for _, t in ipairs(type_def.types) do
            table.insert(type_docs, render_type(t))
        end
        return render_builders.build_separated_docs(type_docs, " | ")
    elseif type_def is parser.TupleType then
        local type_docs: {doc.Doc} = {}
        for _, t in ipairs(type_def.tuple) do
            table.insert(type_docs, render_type(t))
        end
        local result = render_builders.build_separated_docs(type_docs, ", ")
        if type_def.is_va then
            return doc.concat({result, doc.text("...")})
        end
        return result
    elseif type_def is parser.MapType then
        return doc.concat(
            {
                doc.text("{"),
                render_type(type_def.keys),
                doc.text(": "),
                render_type(type_def.values),
                doc.text("}"),
            }
        )
    elseif type_def is parser.TypeVarType then
        return doc.text(type_def.typevar)
    elseif type_def is parser.FunctionType then
        return function_type_render(type_def, generic_doc)
    elseif type_def is parser.TypeDeclType then
        assert(false, "implementation error, does not support enum/interface/...")
    elseif type_def is parser.TupleTableType then
        local type_docs: {doc.Doc} = {}
        for _, t in ipairs(type_def.types) do
            table.insert(type_docs, render_type(t))
        end
        return doc.concat(
            {
                doc.text("{"),
                render_builders.build_separated_docs(type_docs, ", "),
                doc.text("}"),
            }
        )
    elseif type_def is parser.GenericType then
        return type_doc_render(type_def.t, type_doc.render_typeargs(type_def.typeargs))
    elseif parser.simple_types[type_def.typename] then
        return doc.text(type_def.typename)
    end

    assert(false, "unhandled type: " .. tostring(type_def.typename))
end

render_type = function(type_def: parser.Type): doc.Doc
    local result = type_doc_render(type_def)
    if type_def.paren then
        result = doc.concat({doc.text("("), result, doc.text(")")})
    end
    return result
end

function type_doc.render(type_def: parser.Type): doc.Doc
    return render_type(type_def)
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
