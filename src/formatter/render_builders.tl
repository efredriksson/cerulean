local doc = require("formatter.doc")
local parser = require("formatter.parser")

local record DelimitedSequenceOptions
    open_delim: string
    close_delim: string
    compact_indent_amount: integer
end

local render_builders = {DelimitedSequenceOptions = DelimitedSequenceOptions}

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

function render_builders.build_comma_line_item_docs(item_docs: {doc.Doc}): {doc.Doc}
    local result: {doc.Doc} = {}

    for index, item_doc in ipairs(item_docs) do
        table.insert(result, item_doc)
        if index < #item_docs then
            table.insert(result, doc.text(","))
            table.insert(result, doc.line())
        end
    end

    return result
end

function render_builders.build_comment_lines_doc(comments: {parser.Comment}): {doc.Doc}
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

function render_builders.node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

function render_builders.call_arg_effective_end_line(node: parser.Node): integer
    local end_line = render_builders.node_end_line(node)
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

function render_builders.classify_comments_by_previous_end_line(
    node: parser.Node, previous_end_line: integer
): {parser.Comment}, {parser.Comment}
    local trailing: {parser.Comment} = {}
    local leading: {parser.Comment} = {}

    if node.comments ~= nil then
        for _, comment in ipairs(node.comments) do
            if comment.y <= previous_end_line then
                table.insert(trailing, comment)
            else
                table.insert(leading, comment)
            end
        end
    end

    return trailing, leading
end

function render_builders.build_broken_delimited_sequence_doc_from_items(
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

function render_builders.build_broken_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
): doc.Doc
    if #item_docs == 0 then
        return doc.text(opts.open_delim .. opts.close_delim)
    end

    return render_builders.build_broken_delimited_sequence_doc_from_items(
        doc.group(doc.concat(render_builders.build_comma_line_item_docs(item_docs))),
        opts
    )
end

function render_builders.build_grouped_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
): doc.Doc
    return doc.group(
        render_builders.build_broken_delimited_sequence_doc(item_docs, opts)
    )
end

return render_builders
