local doc = require("cerulean.doc")
local parser = require("cerulean.parser")
local render_context = require("cerulean.render_context")

local type RenderContext = render_context.RenderContext

local record DelimitedSequenceOptions
    open_delim: string
    close_delim: string
end

local render_builders = {
    DelimitedSequenceOptions = DelimitedSequenceOptions,
}

function DelimitedSequenceOptions.new(
    open_delim: string, close_delim: string
): DelimitedSequenceOptions
    local self: DelimitedSequenceOptions = setmetatable(
        {}, {__index = DelimitedSequenceOptions}
    )
    self.open_delim = open_delim
    self.close_delim = close_delim
    return self
end

function render_builders.build_comma_line_item_docs(item_docs: {doc.Doc}): doc.Doc
    local parts: {doc.Doc} = {}

    for index, item_doc in ipairs(item_docs) do
        table.insert(parts, item_doc)
        if index < #item_docs then
            table.insert(parts, doc.text(","))
            table.insert(parts, doc.line())
        end
    end

    return doc.concat(parts)
end

function render_builders.build_separated_docs(
    item_docs: {doc.Doc}, separator: string
): doc.Doc
    local parts: {doc.Doc} = {}
    for index, item_doc in ipairs(item_docs) do
        table.insert(parts, item_doc)
        if index < #item_docs then
            table.insert(parts, doc.text(separator))
        end
    end
    return doc.concat(parts)
end

function render_builders.build_comma_separated_docs(item_docs: {doc.Doc}): doc.Doc
    return render_builders.build_separated_docs(item_docs, ", ")
end

function render_builders.build_mapped_comma_separated_docs(
    ctx: RenderContext, nodes: {parser.Node}
): doc.Doc
    local item_docs: {doc.Doc} = {}
    for _, node in ipairs(nodes) do
        table.insert(item_docs, ctx.render_expr(node))
    end
    return render_builders.build_comma_separated_docs(item_docs)
end

function render_builders.build_delimited_body_doc(
    items_doc: doc.Doc, opts: DelimitedSequenceOptions, line_doc: doc.Doc
): doc.Doc
    return doc.concat(
        {
            doc.text(opts.open_delim),
            doc.indent(doc.concat({line_doc, items_doc})),
            line_doc,
            doc.text(opts.close_delim),
        }
    )
end

function render_builders.build_broken_delimited_sequence_doc_from_items(
    items_doc: doc.Doc, opts: DelimitedSequenceOptions
): doc.Doc
    return render_builders.build_delimited_body_doc(items_doc, opts, doc.softline())
end

function render_builders.build_broken_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
): doc.Doc
    if #item_docs == 0 then
        return doc.text(opts.open_delim .. opts.close_delim)
    end

    return render_builders.build_broken_delimited_sequence_doc_from_items(
        doc.group(render_builders.build_comma_line_item_docs(item_docs)), opts
    )
end

function render_builders.build_grouped_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
): doc.Doc
    return doc.group(
        render_builders.build_broken_delimited_sequence_doc(item_docs, opts)
    )
end

function render_builders.build_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
): doc.Doc
    return render_builders.build_grouped_delimited_sequence_doc(item_docs, opts)
end

function render_builders.trailing_comment_doc(node: parser.Node): doc.Doc
    if node.trailing_comment then
        return doc.text(" " .. node.trailing_comment.text)
    end
    return doc.text("")
end

function render_builders.head_trailing_comment_doc(node: parser.Node): doc.Doc
    if node.head_trailing_comment then
        return doc.text(" " .. node.head_trailing_comment.text)
    end
    return doc.text("")
end

function render_builders.any_items_have_comments(items: parser.Node): boolean
    for _, item in ipairs(items) do
        if #(item.comments or {}) > 0 or item.trailing_comment then
            return true
        end
    end
    return false
end

function render_builders.build_exp_list_doc(
    ctx: RenderContext, exps: {parser.Node}
): doc.Doc
    if not render_builders.any_items_have_comments(exps) then
        return render_builders.build_mapped_comma_separated_docs(ctx, exps)
    end
    local parts: {doc.Doc} = {}
    local force_next_indent = false
    for index, exp in ipairs(exps) do
        local is_last = index == #exps
        local exp_doc = ctx.render_expr(exp)
        if force_next_indent then
            exp_doc = doc.indent_hardline(exp_doc)
            force_next_indent = false
        end
        if not is_last then
            if exp.trailing_comment then
                exp_doc = doc.concat(
                    {exp_doc, doc.text(","), doc.text(" " .. exp.trailing_comment.text)}
                )
                force_next_indent = true
            else
                exp_doc = doc.concat({exp_doc, doc.text(", ")})
            end
        end
        table.insert(parts, exp_doc)
    end
    return doc.concat(parts)
end

function render_builders.block_has_any_comments(block: parser.Node): boolean
    return render_builders.any_items_have_comments(block)
        or #(block.end_comments or {}) > 0
end

function render_builders.item_line_doc(should_force_wrap: boolean): doc.Doc
    if should_force_wrap then
        return doc.hardline()
    else
        return doc.softline()
    end
end

function render_builders.append_lines_pre_node(
    node: parser.Node | parser.FieldEntry,
    line_before: boolean,
    line_from_before?: doc.Doc
): doc.Doc
    local parts: {doc.Doc} = {}
    if line_before then
        table.insert(parts, line_from_before or doc.softline())
    end
    if node.blank_line_before then
        table.insert(parts, doc.hardline())
    end

    return doc.concat(parts)
end

function render_builders.with_leading_inline_comment(
    node: parser.Node, prefix: doc.Doc, content: doc.Doc
): doc.Doc
    if node.leading_inline_comment then
        return doc.concat(
            {
                prefix,
                doc.text(node.leading_inline_comment.text),
                doc.indent_hardline(content),
            }
        )
    end
    return doc.concat({prefix, content})
end

function render_builders.append_comment_docs(
    parts: {doc.Doc}, comments: {parser.Comment}, line_before: boolean
): boolean
    for _, comment in ipairs(comments) do
        if line_before then
            table.insert(parts, doc.hardline())
        end
        if comment.blank_line_before then
            table.insert(parts, doc.hardline())
        end
        table.insert(parts, doc.text(comment.text))
        line_before = true
    end
    return line_before
end

return render_builders
