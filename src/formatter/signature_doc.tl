-- Function parameter list → doc.Doc.
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")

local signature_doc = {}

local function build_signature_item_doc(arg_node: parser.Node): doc.Doc
    local parts: {doc.Doc} = {
        doc.text(arg_node.tk),
    }

    if arg_node.opt == true and arg_node.tk ~= "..." then
        table.insert(parts, doc.text("?"))
    end

    if arg_node.argtype ~= nil then
        local type_text = assert(
            arg_node.argtype.source_text,
            "missing source_text for signature argument type"
        )
        table.insert(parts, doc.text(": "))
        table.insert(parts, doc.text(type_text))
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

local function build_delimited_sequence_doc(
    item_docs: {doc.Doc},
    opts: render_builders.DelimitedSequenceOptions,
    compact_when_possible: boolean
): doc.Doc
    local result = render_builders.build_delimited_sequence_doc(item_docs, opts)
    if compact_when_possible then
        return doc.group(result)
    end
    return result
end

function signature_doc.render_signature_doc(
    args: parser.Node, force_wrap?: boolean
): doc.Doc
    local opts = render_builders.DelimitedSequenceOptions.new("(", ")", 4)
    local item_docs = build_signature_item_docs(args)
    local should_force_wrap = force_wrap or false

    return build_delimited_sequence_doc(item_docs, opts, not should_force_wrap)
end

return signature_doc
