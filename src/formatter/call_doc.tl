-- Function call args AST list → doc.Doc (build_call_expr_doc) or {string} (render_call).
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local render_context = require("formatter.render_context")

local type RenderContext = render_context.RenderContext

local call_doc = {}

function call_doc.build_call_expr_doc(ctx: RenderContext, node: parser.Node): doc.Doc
    local callee_doc = ctx.render_expr(node.e1)
    local line_items = render_builders.CommentLineItems.new()
    for _, arg_node in ipairs(node.e2) do
        line_items:add(
            ctx.render_expr(arg_node),
            render_builders.node_effective_end_line(arg_node),
            arg_node.comments or {},
            false
        )
    end
    local has_inline_comments = line_items.has_comments
    local has_trailing_comment = node.e2.trailing_comment ~= nil

    local item_docs: {doc.Doc} = {}
    for _, arg_node in ipairs(node.e2) do
        table.insert(item_docs, ctx.render_expr(arg_node))
    end
    local opts = render_builders.DelimitedSequenceOptions.new("(", ")", 4)

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
