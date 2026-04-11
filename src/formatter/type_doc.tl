local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")

local render_return: function(parser.TupleType): doc.Doc

local function arg_name_doc(arg_name: string): doc.Doc
    if arg_name ~= nil then
        return doc.text(arg_name .. ": ")
    else
        return doc.text("")
    end
end

local function type_doc_render(type_def: parser.Type): doc.Doc
    if type_def is parser.NominalType then
        local parts: {doc.Doc} = {doc.text(table.concat(type_def.names, "."))}
        if type_def.typevals ~= nil and #type_def.typevals > 0 then
            local typevals: {string} = {}
            for _, typeval in ipairs(type_def.typevals) do
                if typeval.source_text == nil or typeval.source_text == "" then
                    return nil
                end
                table.insert(typevals, typeval.source_text)
            end
            table.insert(parts, doc.text("<" .. table.concat(typevals, ", ") .. ">"))
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
            table.insert(
                arg_docs,
                doc.concat({arg_name_doc(argnames[index]), type_doc_render(arg_type)})
            )
        end
        local parts: {doc.Doc} = {
            doc.text("function("),
            render_builders.build_separated_docs(arg_docs, ", "),
            doc.text(")"),
            render_return(type_def.rets),
        }
        return doc.concat(parts)
    elseif parser.simple_types[type_def.typename] then
        return doc.text(type_def.typename)
    end

    if type_def.source_text ~= nil and type_def.source_text ~= "" then
        return doc.text(type_def.source_text)
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
