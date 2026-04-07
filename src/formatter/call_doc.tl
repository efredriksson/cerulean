-- Function call args AST list → doc.Doc (build_call_expr_doc) or {string} (render_call).
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")

local call_doc = {}

local type RenderCallee = function(parser.Node): doc.Doc
local type RenderArg = function(parser.Node): doc.Doc

local function args_have_inline_comments(args: parser.Node): boolean
    for _, call_arg in ipairs(args) do
        if call_arg.comments ~= nil and #call_arg.comments > 0 then
            return true
        end
    end
    return false
end

local function build_call_arg_items_doc_with_comments(
    args: parser.Node, render_arg: RenderArg
): doc.Doc
    local parts: {doc.Doc} = {}
    local prev_arg_end_line: integer | nil = nil

    for index, arg_node in ipairs(args) do
        local trailing_comments: {parser.Comment} = {}
        local leading_comments: {parser.Comment} = arg_node.comments or {}
        if not (prev_arg_end_line is nil) then
            local non_nil_prev_arg_end_line = prev_arg_end_line
            trailing_comments, leading_comments = render_builders.classify_comments_by_previous_end_line(
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
            for _, comment_part in ipairs(
                render_builders.build_comment_lines_doc(leading_comments)
            ) do
                table.insert(parts, comment_part)
            end
            table.insert(parts, doc.hardline())
        end

        table.insert(parts, render_arg(arg_node))
        prev_arg_end_line = render_builders.call_arg_effective_end_line(arg_node)
    end

    return doc.concat(parts)
end

local function build_call_arg_item_docs(
    args: parser.Node, render_arg: RenderArg
): {doc.Doc}
    local result: {doc.Doc} = {}
    for _, arg_node in ipairs(args) do
        table.insert(result, render_arg(arg_node))
    end
    return result
end

function call_doc.build_call_expr_doc(
    node: parser.Node, render_callee: RenderCallee, render_arg: RenderArg
): doc.Doc
    local callee_doc = render_callee(node.e1)
    local item_docs = build_call_arg_item_docs(node.e2, render_arg)
    local opts = render_builders.DelimitedSequenceOptions.new("(", ")", 4)
    local has_inline_comments = args_have_inline_comments(node.e2)
    local has_trailing_comment = node.e2.trailing_comment ~= nil

    local call_args_doc: doc.Doc
    if has_inline_comments then
        call_args_doc = render_builders.build_broken_delimited_sequence_doc_from_items(
            build_call_arg_items_doc_with_comments(node.e2, render_arg), opts
        )
    else
        call_args_doc = render_builders.build_delimited_sequence_doc(item_docs, opts)
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
    if has_inline_comments then
        return call_node
    end
    return doc.group(call_node)
end

return call_doc
