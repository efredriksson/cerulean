-- Function call args AST list → doc.Doc (build_call_expr_doc) or {string} (render_call).
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")

local call_doc = {}

local type Renderer = function(parser.Node): doc.Doc

local function build_call_arg_item_docs(
    args: parser.Node, render_arg: Renderer
): {doc.Doc}
    local result: {doc.Doc} = {}
    for _, arg_node in ipairs(args) do
        table.insert(result, render_arg(arg_node))
    end
    return result
end

function call_doc.build_call_expr_doc(node: parser.Node, render_arg: Renderer): doc.Doc
    local callee_doc = render_arg(node.e1)
    local item_docs = build_call_arg_item_docs(node.e2, render_arg)
    local opts = render_builders.DelimitedSequenceOptions.new("(", ")", 4)
    local line_items = render_builders.CommentLineItems.new()
    for _, arg_node in ipairs(node.e2) do
        line_items:add(
            render_arg(arg_node),
            render_builders.node_effective_end_line(arg_node),
            arg_node.comments or {},
            false
        )
    end
    local has_inline_comments = line_items.has_comments
    local has_trailing_comment = node.e2.trailing_comment ~= nil

    local call_args_doc: doc.Doc
    if has_inline_comments then
        local function item_suffix(
            _entry: render_builders.LineEntry, is_final: boolean
        ): doc.Doc
            if is_final then
                return doc.text("")
            end
            return doc.text(",")
        end

        local function entry_separator(
            _ctx: render_builders.EntrySeparatorContext
        ): doc.Doc
            return doc.hardline()
        end

        call_args_doc = render_builders.build_broken_delimited_sequence_doc_from_items(
            render_builders.render_line_entries(
                line_items, item_suffix, entry_separator
            ),
            opts
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
