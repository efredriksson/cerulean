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
        return doc.group(doc.concat({
            doc.text(opts.open_delim),
            doc.indent(opts.compact_indent_amount, doc.concat({
                doc.line(""),
                item_docs[1],
            })),
            doc.line(""),
            doc.text(opts.close_delim),
        }))
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
        doc.indent(4, doc.concat({
            doc.line(""),
            doc.concat(parts),
        })),
        doc.line(""),
        doc.text(")"),
    })
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
    if args_have_inline_comments(args) then
        lines = render_doc(
            build_delimited_sequence_doc(item_docs, opts, false), indent_prefix
        )
    elseif compact or #item_docs == 0 then
        lines = render_doc(
            build_compact_delimited_sequence_doc(item_docs, opts), indent_prefix
        )
    elseif #item_docs == 1 then
        local compact_line = render_doc(
            build_compact_delimited_sequence_doc(item_docs, opts), indent_prefix
        )
        local wrapped = wrap_construct_lines(prefix, suffix, compact_line)
        if #wrapped == 1 and #wrapped[1] <= 88 then
            lines = compact_line
        else
            lines = build_delimited_sequence_doc(item_docs, opts, true):render(
                88 - #suffix, #prefix, #indent_prefix, true
            )
        end
    elseif prefer_trailing_compact then
        local compact_lines = render_doc(
            build_trailing_call_doc(item_docs), indent_prefix
        )
        if #compact_lines == 3 and #compact_lines[2] <= 88 then
            lines = compact_lines
        else
            lines = build_delimited_sequence_doc(item_docs, opts, true):render(
                88 - #suffix, #prefix, #indent_prefix, true
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
    local callee_doc = expr_doc.render_expr(node.e1)
    local item_docs = build_call_arg_item_docs(node.e2)
    local opts = DelimitedSequenceOptions.new("(", ")", 4)
    -- Wrap in a group so the renderer tries the compact (flat) form first.
    -- Without a group the doc.line breaks inside build_delimited_sequence_doc
    -- always expand, wrapping even short calls that fit on one line.
    if args_have_inline_comments(node.e2) or node.e2.trailing_comment ~= nil then
        local call_node = doc.concat({
            callee_doc,
            build_delimited_sequence_doc(item_docs, opts, false),
        })
        if node.e2.trailing_comment ~= nil then
            return doc.concat({
                call_node,
                doc.text(" " .. node.e2.trailing_comment.text),
            })
        end
        return call_node
    end
    return doc.group(doc.concat({
        callee_doc,
        build_delimited_sequence_doc(item_docs, opts, true),
    }))
end

return call_doc
