local doc = require("formatter.doc")
local parser = require("formatter.parser")

local table_doc = {}

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

local function build_table_item_text(
    item: parser.Node, render_expr: function(parser.Node): string
): string
    if item.key_parsed == "implicit" then
        return render_expr(item.value)
    elseif item.key_parsed == "short" then
        local key_text = item.key.conststr or item.key.tk
        if item.itemtype ~= nil then
            return key_text
                .. ": "
                .. assert(
                    item.itemtype.source_text, "missing source_text for table item type"
                )
                .. " = "
                .. render_expr(item.value)
        end
        return key_text .. " = " .. render_expr(item.value)
    end

    return "["
        .. render_expr(item.key)
        .. "] = "
        .. render_expr(item.value)
end

function table_doc.render_table_text(
    node: parser.Node, render_expr: function(parser.Node): string
): string
    local parts: {string} = {}

    for _, item in ipairs(node) do
        table.insert(parts, build_table_item_text(item, render_expr))
    end

    return "{" .. table.concat(parts, ", ") .. "}"
end

local function build_table_item_docs(
    node: parser.Node, render_expr: function(parser.Node): string
): {doc.Doc}
    local result: {doc.Doc} = {}

    for _, item in ipairs(node) do
        table.insert(result, doc.text(build_table_item_text(item, render_expr)))
    end

    return result
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
        else
            table.insert(item_parts, doc.break_text(","))
        end
        table.insert(result, doc.concat(item_parts))
    end

    return result
end

local function build_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
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

    return doc.concat({
        doc.text(opts.open_delim),
        doc.indent(opts.compact_indent_amount, doc.concat({
            doc.line(""),
            doc.group(doc.concat(build_item_docs(item_docs))),
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

function table_doc.render_table(
    node: parser.Node,
    prefix: string,
    suffix: string,
    compact: boolean,
    render_expr: function(parser.Node): string
): {string}
    local opts = DelimitedSequenceOptions.new("{", "}", 4)
    local indent_prefix = prefix:match("^(%s*)") or ""
    local item_docs = build_table_item_docs(node, render_expr)

    local lines: {string}
    if compact or #item_docs < 2 then
        lines = render_doc(
            build_compact_delimited_sequence_doc(item_docs, opts), indent_prefix
        )
    else
        lines = render_doc(build_delimited_sequence_doc(item_docs, opts), indent_prefix)
    end

    return wrap_construct_lines(prefix, suffix, lines)
end

return table_doc
