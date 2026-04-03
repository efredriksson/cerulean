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
        local item_parts: {doc.Doc} = {
            item_doc,
        }
        if i < #item_docs then
            table.insert(item_parts, doc.text(","))
            table.insert(item_parts, doc.line(" "))
        end
        table.insert(result, doc.concat(item_parts))
    end

    return result
end

local function build_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions, compact_when_possible: boolean
): doc.Doc
    if #item_docs == 0 then
        return doc.text(opts.open_delim .. opts.close_delim)
    elseif #item_docs == 1 then
        return doc.concat({
            doc.text(opts.open_delim),
            item_docs[1],
            doc.text(opts.close_delim),
        })
    end

    local item_doc = doc.concat(build_item_docs(item_docs))
    if compact_when_possible then
        item_doc = doc.group(item_doc)
    end

    return doc.concat({
        doc.text(opts.open_delim),
        doc.indent(opts.compact_indent_amount, doc.concat({
            doc.line(""),
            item_doc,
        })),
        doc.line(""),
        doc.text(opts.close_delim),
    })
end

local function build_compact_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
): doc.Doc
    local parts: {doc.Doc} = {
        doc.text(opts.open_delim),
    }

    for i, item_doc in ipairs(item_docs) do
        table.insert(parts, item_doc)
        if i < #item_docs then
            table.insert(parts, doc.text(", "))
        end
    end

    table.insert(parts, doc.text(opts.close_delim))
    return doc.concat(parts)
end

local function build_trailing_call_doc(item_docs: {doc.Doc}): doc.Doc
    if #item_docs < 2 then
        return build_compact_delimited_sequence_doc(
            item_docs, DelimitedSequenceOptions.new("(", ")", 4)
        )
    end

    local parts: {doc.Doc} = {}
    for i, item_doc in ipairs(item_docs) do
        table.insert(parts, item_doc)
        if i < #item_docs then
            table.insert(parts, doc.text(", "))
        end
    end

    return doc.concat({
        doc.text("("),
        doc.indent(3, doc.concat({
            doc.line(""),
            doc.concat(parts),
        })),
        doc.line(""),
        doc.text(")"),
    })
end

local function build_call_arg_doc(node: parser.Node): doc.Doc
    if node.kind == "literal_table" then
        return doc.group(table_doc.build_table_doc(node, expr_doc.render_expr))
    end
    return doc.text(expr_doc.render_expr(node))
end

local function build_call_arg_item_docs(args: parser.Node): {doc.Doc}
    local result: {doc.Doc} = {}
    for _, arg_node in ipairs(args) do
        table.insert(result, build_call_arg_doc(arg_node))
    end
    return result
end

local function render_doc(node: doc.Doc, indent_prefix: string): {string}
    return node:render(88, 0, #indent_prefix, true)
end

local function wrap_construct_lines(
    prefix: string, suffix: string, lines: {string}
): {string}
    local result: {string} = {}

    for i, line_str in ipairs(lines) do
        if i == 1 and i == #lines then
            table.insert(result, prefix .. line_str .. suffix)
        elseif i == 1 then
            table.insert(result, prefix .. line_str)
        elseif i == #lines then
            table.insert(result, line_str .. suffix)
        else
            table.insert(result, line_str)
        end
    end

    return result
end

function call_doc.render_call(
    args: parser.Node,
    prefix: string,
    suffix: string,
    compact: boolean,
    prefer_trailing_compact: boolean
): {string}
    local opts = DelimitedSequenceOptions.new("(", ")", 4)
    local indent_prefix = prefix:match("^(%s*)") or ""
    local item_docs = build_call_arg_item_docs(args)

    local lines: {string}
    if compact or #item_docs < 2 then
        lines = render_doc(
            build_compact_delimited_sequence_doc(item_docs, opts), indent_prefix
        )
    elseif prefer_trailing_compact then
        local compact_lines = render_doc(
            build_trailing_call_doc(item_docs), indent_prefix
        )
        if #compact_lines == 3 and #compact_lines[2] <= 88 then
            lines = compact_lines
        else
            lines = render_doc(
                build_delimited_sequence_doc(item_docs, opts, true), indent_prefix
            )
        end
    elseif suffix ~= "" then
        lines = render_doc(
            build_delimited_sequence_doc(item_docs, opts, false), indent_prefix
        )
    else
        lines = render_doc(
            build_delimited_sequence_doc(item_docs, opts, true), indent_prefix
        )
    end

    return wrap_construct_lines(prefix, suffix, lines)
end

function call_doc.build_call_expr_doc(node: parser.Node): doc.Doc
    local callee_text = expr_doc.render_expr(node.e1)
    local item_docs = build_call_arg_item_docs(node.e2)
    local opts = DelimitedSequenceOptions.new("(", ")", 4)
    return doc.concat({
        doc.text(callee_text),
        build_delimited_sequence_doc(item_docs, opts, true),
    })
end

return call_doc
