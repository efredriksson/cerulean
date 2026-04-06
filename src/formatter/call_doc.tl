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
            table.insert(result, doc.line())
        end
    end

    return result
end

local function build_comment_lines_doc(comments: {parser.Comment}): {doc.Doc}
    local parts: {doc.Doc} = {}
    for index, comment in ipairs(comments) do
        if index > 1 then
            table.insert(parts, doc.hardline())
        end
        if index > 1 and comment.blank_line_before then
            table.insert(parts, doc.hardline())
        end
        table.insert(parts, doc.text(comment.text))
    end
    return parts
end

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function call_arg_effective_end_line(node: parser.Node): integer
    local end_line = node_end_line(node)
    if node.kind == "op"
        and node.op ~= nil
        and node.op.op == "@funcall"
        and node.e2 ~= nil
        and node.e2.yend ~= nil
        and node.e2.yend > end_line then
        end_line = node.e2.yend
    end
    return end_line
end

local function classify_arg_comments(
    node: parser.Node, prev_arg_end_line: integer
): {parser.Comment}, {parser.Comment}
    local trailing: {parser.Comment} = {}
    local leading: {parser.Comment} = {}
    if node.comments ~= nil then
        for _, comment in ipairs(node.comments) do
            if comment.y <= prev_arg_end_line then
                table.insert(trailing, comment)
            else
                table.insert(leading, comment)
            end
        end
    end
    return trailing, leading
end

local function build_broken_delimited_sequence_doc_from_items(
    items_doc: doc.Doc, opts: DelimitedSequenceOptions
): doc.Doc
    return doc.concat(
        {
            doc.text(opts.open_delim),
            doc.indent(
                opts.compact_indent_amount,
                doc.concat(
                    {
                        doc.softline(),
                        items_doc,
                    }
                )
            ),
            doc.softline(),
            doc.text(opts.close_delim),
        }
    )
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
    return doc.group(build_broken_delimited_sequence_doc(item_docs, opts))
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

local function build_call_arg_items_doc_with_comments(args: parser.Node): doc.Doc
    local parts: {doc.Doc} = {}
    local prev_arg_end_line: integer | nil = nil

    for index, arg_node in ipairs(args) do
        local trailing_comments: {parser.Comment} = {}
        local leading_comments: {parser.Comment} = arg_node.comments or {}
        if not (prev_arg_end_line is nil) then
            local non_nil_prev_arg_end_line = prev_arg_end_line
            trailing_comments, leading_comments = classify_arg_comments(
                arg_node, non_nil_prev_arg_end_line
            )
        end

        if index > 1 then
            table.insert(parts, doc.text(","))
            if #trailing_comments > 0 then
                for _, comment in ipairs(trailing_comments) do
                    table.insert(parts, doc.text(" " .. comment.text))
                end
            end
            table.insert(parts, doc.hardline())
        end

        if #leading_comments > 0 then
            for _, comment_part in ipairs(build_comment_lines_doc(leading_comments)) do
                table.insert(parts, comment_part)
            end
            table.insert(parts, doc.hardline())
        end

        table.insert(parts, build_call_arg_doc(arg_node))
        prev_arg_end_line = call_arg_effective_end_line(arg_node)
    end

    return doc.concat(parts)
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
    local has_inline_comments = args_have_inline_comments(node.e2)
    local has_trailing_comment = node.e2.trailing_comment ~= nil
    local call_args_doc = build_delimited_sequence_doc(item_docs, opts)
    if has_inline_comments or has_trailing_comment then
        call_args_doc = build_broken_delimited_sequence_doc(item_docs, opts)
    end
    if has_inline_comments then
        call_args_doc = build_broken_delimited_sequence_doc_from_items(
            build_call_arg_items_doc_with_comments(node.e2), opts
        )
    end
    local call_node = doc.concat(
        {
            callee_doc,
            call_args_doc,
        }
    )
    if has_trailing_comment then
        return doc.concat(
            {
                call_node,
                doc.text(" " .. node.e2.trailing_comment.text),
            }
        )
    end
    if has_inline_comments or has_trailing_comment then
        return call_node
    end
    return doc.group(call_node)
end

return call_doc
