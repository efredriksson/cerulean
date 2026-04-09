-- Function parameter list → doc.Doc.
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local type_doc = require("formatter.type_doc")

local signature_doc = {}

local function build_signature_item_doc(arg_node: parser.Node): doc.Doc
    local parts: {doc.Doc} = {
        doc.text(arg_node.tk),
    }

    if arg_node.opt == true and arg_node.tk ~= "..." then
        table.insert(parts, doc.text("?"))
    end

    if arg_node.argtype ~= nil then
        table.insert(parts, doc.text(": "))
        table.insert(parts, type_doc.render(arg_node.argtype))
    end

    return doc.concat(parts)
end

local function build_signature_item_docs(args: parser.Node): {doc.Doc}
    local result: {doc.Doc} = {}

    for _, arg_node in ipairs(args) do
        if arg_node.kind == "argument" then
            table.insert(result, build_signature_item_doc(arg_node))
        end
    end

    return result
end

function signature_doc.render_signature_doc(args: parser.Node): doc.Doc
    local opts = render_builders.DelimitedSequenceOptions.new("(", ")", 4)
    local item_docs = build_signature_item_docs(args)

    return doc.group(render_builders.build_delimited_sequence_doc(item_docs, opts))
end

return signature_doc
