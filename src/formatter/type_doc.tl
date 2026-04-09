local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")

local type_doc = {}

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
    elseif parser.simple_types[type_def.typename] then
        return doc.text(type_def.typename)
    end

    if type_def.source_text ~= nil and type_def.source_text ~= "" then
        return doc.text(type_def.source_text)
    end

    assert(false, "unhandled type: " .. tostring(type_def.typename))
end

function type_doc.render(type_def: parser.Type): doc.Doc
    local type_doc_res = type_doc_render(type_def)
    if type_def.paren then
        type_doc_res = doc.concat({doc.text("("), type_doc_res, doc.text(")")})
    end

    return type_doc_res
end

return type_doc
