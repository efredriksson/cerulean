-- Function parameter list → {string} (render_signature) or compact string (render_signature_text).
-- render_signature is used by the span pass in rewriter.tl.
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local tl = require("tl")

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

local function build_signature_item_text(arg_node: parser.Node): string
    local text = arg_node.tk

    if arg_node.opt == true and arg_node.tk ~= "..." then
        text = text .. "?"
    end

    if arg_node.argtype ~= nil then
        text = text .. ": " .. assert(
            arg_node.argtype.source_text,
            "missing source_text for signature argument type"
        )
    end

    return text
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
    local result = render_builders.build_broken_delimited_sequence_doc(item_docs, opts)
    if compact_when_possible then
        return doc.group(result)
    end
    return result
end

local function build_compact_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: render_builders.DelimitedSequenceOptions
): doc.Doc
    local parts: {doc.Doc} = {
        doc.text(opts.open_delim),
    }

    for index, item_doc in ipairs(item_docs) do
        table.insert(parts, item_doc)
        if index < #item_docs then
            table.insert(parts, doc.text(", "))
        end
    end

    table.insert(parts, doc.text(opts.close_delim))
    return doc.concat(parts)
end

function signature_doc.render_signature_text(
    args: parser.Node, rets: tl.TupleType | nil
): string
    local parts: {string} = {}

    for _, arg_node in ipairs(args) do
        if arg_node.kind == "argument" then
            table.insert(parts, build_signature_item_text(arg_node))
        end
    end

    local result = "(" .. table.concat(parts, ", ") .. ")"
    local rets_source_text: string = ""
    if not (rets is nil) then
        rets_source_text = rets.source_text or ""
    end

    if rets_source_text ~= "" then
        result = result .. rets_source_text
    end
    return result
end

function signature_doc.render_signature_doc(
    args: parser.Node, compact: boolean, force_wrap?: boolean
): doc.Doc
    local opts = render_builders.DelimitedSequenceOptions.new("(", ")", 4)
    local item_docs = build_signature_item_docs(args)
    local should_force_wrap = force_wrap or false

    if compact or #item_docs < 2 then
        return build_compact_delimited_sequence_doc(item_docs, opts)
    else
        return build_delimited_sequence_doc(item_docs, opts, not should_force_wrap)
    end
end

return signature_doc
