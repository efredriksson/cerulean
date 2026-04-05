-- Function call args AST list → doc.Doc (build_call_expr_doc) or {string} (render_call).
local doc = require("formatter.doc")
local expr_doc = require("formatter.expr_doc")
local parser = require("formatter.parser")
local table_doc = require("formatter.table_doc")

local call_doc = {}

local record DelimitedSequenceOptions
    open_delim: string
    close_delim: string
    compact_indent_amount: integer
end

function DelimitedSequenceOptions.new(
    open_delim: string, close_delim: string, compact_indent_amount: integer
): DelimitedSequenceOptions
    local self: DelimitedSequenceOptions = setmetatable(
        {}, {__index = DelimitedSequenceOptions}
    )
    self.open_delim = open_delim
    self.close_delim = close_delim
    self.compact_indent_amount = compact_indent_amount
    return self
end

local function build_item_docs(item_docs: {doc.Doc}): {doc.Doc}
    local result: {doc.Doc} = {}

    for i, item_doc in ipairs(item_docs) do
        table.insert(result, item_doc)
        if i < #item_docs then
            table.insert(result, doc.text(","))
            table.insert(result, doc.line(" "))
        end
    end

    return result
end

local function build_broken_delimited_sequence_doc_from_items(
    items_doc: doc.Doc, opts: DelimitedSequenceOptions
): doc.Doc
    return doc.concat({
        doc.text(opts.open_delim),
        doc.indent(opts.compact_indent_amount, doc.concat({
            doc.line(""),
            items_doc,
        })),
        doc.line(""),
        doc.text(opts.close_delim),
    })
end

local function build_broken_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
): doc.Doc
    if #item_docs == 0 then
        return doc.text(opts.open_delim .. opts.close_delim)
    end

    return build_broken_delimited_sequence_doc_from_items(
        doc.group(doc.concat(build_item_docs(item_docs))), opts
    )
end

local function build_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
): doc.Doc
    return doc.group(build_broken_delimited_sequence_doc(
        item_docs, opts
    ))
end

local function args_have_inline_comments(args: parser.Node): boolean
    for _, call_arg in ipairs(args) do
        if call_arg.comments ~= nil and #call_arg.comments > 0 then
            return true
        end
    end
    return false
end

local function build_call_arg_doc(node: parser.Node): doc.Doc
    if node.kind == "literal_table" then
        return doc.group(table_doc.build_table_doc(node, expr_doc.render_expr))
    end
    return expr_doc.render_expr(node)
end

local function build_call_arg_item_docs(args: parser.Node): {doc.Doc}
    local result: {doc.Doc} = {}
    for _, arg_node in ipairs(args) do
        table.insert(result, build_call_arg_doc(arg_node))
    end
    return result
end

function call_doc.build_call_expr_doc(node: parser.Node): doc.Doc
    local callee_doc = expr_doc.render_expr(node.e1)
    local item_docs = build_call_arg_item_docs(node.e2)
    local opts = DelimitedSequenceOptions.new("(", ")", 4)
    -- Wrap in a group so the renderer tries the compact (flat) form first.
    -- Without a group the doc.line breaks inside build_delimited_sequence_doc
    -- always expand, wrapping even short calls that fit on one line.
    if args_have_inline_comments(node.e2) or node.e2.trailing_comment ~= nil then
        local call_node = doc.concat({
            callee_doc,
            build_broken_delimited_sequence_doc(item_docs, opts),
        })
        if node.e2.trailing_comment ~= nil then
            return doc.concat({
                call_node,
                doc.text(" " .. node.e2.trailing_comment.text),
            })
        end
        return call_node
    end
    local call_args_doc = build_delimited_sequence_doc(item_docs, opts)
    local call_node = doc.concat({
        callee_doc,
        call_args_doc,
    })
    return doc.group(call_node)
end

return call_doc
