local doc = require("cerulean.doc")
local parser = require("cerulean.parser")
local render_context = require("cerulean.render_context")
local trivia_doc = require("cerulean.trivia_doc")

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

function render_builders.normalize_string_literal(
    tk: string, is_longstring: boolean
): string
    if is_longstring then
        return tk
    end
    local content = tk:sub(2, -2)
    if content:find('"', 1, true) then
        return tk
    end
    return '"' .. content .. '"'
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
    local parts: {doc.Doc} = {}
    for _, comment in ipairs(node.trailing_comments or {}) do
        table.insert(parts, doc.text(" " .. comment.text))
    end
    return doc.concat(parts)
end

function render_builders.head_trivia_doc(node: parser.Node): doc.Doc
    local head = parser.inline_trivia(node, "head")
    if #head == 0 then
        return doc.text("")
    end
    local parts: {doc.Doc} = {}
    trivia_doc.append_inline(parts, head)
    return doc.concat(parts)
end

function render_builders.any_items_have_comments(items: parser.Node): boolean
    for _, item in ipairs(items) do
        if
            #(item.leading_comments or {}) > 0 or #(item.trailing_comments or {}) > 0
        then
            return true
        end
    end
    return false
end

local function any_items_have_trailing_trivia(items: {parser.Node}): boolean
    for _, item in ipairs(items) do
        if #parser.inline_trivia(item, "before_separator") > 0 then
            return true
        end
    end
    return false
end

function render_builders.build_exp_list_doc(
    ctx: RenderContext, exps: {parser.Node}
): doc.Doc
    if
        not render_builders.any_items_have_comments(exps)
        and not any_items_have_trailing_trivia(exps)
    then
        return render_builders.build_mapped_comma_separated_docs(ctx, exps)
    end
    local parts: {doc.Doc} = {}
    local force_next_indent = false
    for index, exp in ipairs(exps) do
        local is_last = index == #exps
        local item_parts: {doc.Doc} = {ctx.render_expr(exp)}
        trivia_doc.append_inline(
            item_parts, parser.inline_trivia(exp, "before_separator")
        )
        local exp_doc = doc.concat(item_parts)
        if force_next_indent then
            exp_doc = doc.indent_hardline(exp_doc)
            force_next_indent = false
        end
        if not is_last then
            if #(exp.trailing_comments or {}) > 0 then
                local trailing_parts: {doc.Doc} = {exp_doc, doc.text(",")}
                for _, comment in ipairs(exp.trailing_comments) do
                    table.insert(trailing_parts, doc.text(" " .. comment.text))
                end
                exp_doc = doc.concat(trailing_parts)
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
        or #(block.dangling_comments or {}) > 0
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
    line_from_before?: doc.Doc,
    suppress_blank?: boolean
): doc.Doc
    local parts: {doc.Doc} = {}
    if line_before then
        table.insert(parts, line_from_before or doc.softline())
    end
    if node.blank_line_before and not suppress_blank then
        -- enclosing group MUST break, for example anon function.
        table.insert(parts, doc.concat({doc.hardline(), doc.break_parent()}))
    end

    return doc.concat(parts)
end

function render_builders.is_top_level_binary_op(node: parser.Node): boolean
    if node.kind ~= "op" or node.op == nil then
        return false
    end
    if node.op.arity ~= 2 then
        return false
    end
    local op = node.op.op
    return op ~= "@funcall"
        and op ~= "@index"
        and op ~= "."
        and op ~= ":"
        and op ~= "as"
end

function render_builders.has_chain_internal_trivia(node: parser.Node): boolean
    if node.kind ~= "op" or node.op == nil then
        return false
    end
    if #parser.inline_trivia(node, "op_leading") > 0 then
        return true
    end
    if #parser.inline_trivia(node, "op_trailing") > 0 then
        return true
    end
    if node.e1 ~= nil and render_builders.has_chain_internal_trivia(node.e1) then
        return true
    end
    if node.e2 ~= nil and render_builders.has_chain_internal_trivia(node.e2) then
        return true
    end
    return false
end

function render_builders.wrap_keyword_around(
    keyword: doc.Doc, expression: doc.Doc, closing: doc.Doc
): doc.Doc
    return doc.group(
        doc.concat({keyword, doc.indent_line(expression), doc.line(), closing})
    )
end

function render_builders.wrap_keyword_before(
    keyword: doc.Doc, expression: doc.Doc
): doc.Doc
    return doc.group(doc.concat({keyword, doc.indent_line(expression)}))
end

function render_builders.with_leading_inline_trivia(
    node: parser.Node, prefix: doc.Doc, content: doc.Doc
): doc.Doc
    local after_opener = parser.inline_trivia(node, "after_opener")
    if #after_opener == 0 then
        return doc.concat({prefix, content})
    end
    local parts: {doc.Doc} = {prefix}
    trivia_doc.append_inline_joined(parts, after_opener)
    table.insert(parts, doc.indent_hardline(content))
    return doc.concat(parts)
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

function render_builders.key_starts_with_long_string(node: parser.Node): boolean
    -- When the key expression's leftmost token is a long string, the subscript `[`
    -- must be spaced away to prevent `[[[k]]` from being lexed as a long string.
    return node.is_longstring
        or node.kind == "op"
            and node.op.arity == 2
            and render_builders.key_starts_with_long_string(node.e1)
end

return render_builders
