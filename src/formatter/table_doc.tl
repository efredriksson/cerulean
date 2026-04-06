-- Table constructor → doc.Doc (build_table_doc) or {string} (render_table).
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")

local table_doc = {}

local record TableItemDoc
    item: parser.Node
    comment: parser.Comment
end

function TableItemDoc.new(item: parser.Node, comment: parser.Comment): TableItemDoc
    local self: TableItemDoc = setmetatable({}, {__index = TableItemDoc})
    self.item = item
    self.comment = comment
    return self
end

local function build_table_item_text(
    item: parser.Node, render_expr: function(parser.Node): doc.Doc
): doc.Doc
    if item.key_parsed == "implicit" then
        return render_expr(item.value)
    elseif item.key_parsed == "short" then
        local key_text = item.key.conststr or item.key.tk
        if item.itemtype ~= nil then
            return doc.concat(
                {
                    doc.text(
                        key_text .. ": " .. assert(
                            item.itemtype.source_text,
                            "missing source_text for table item type"
                        ) .. " = "
                    ),
                    render_expr(item.value),
                }
            )
        end
        return doc.concat({doc.text(key_text .. " = "), render_expr(item.value)})
    end

    return doc.concat(
        {
            doc.text("["),
            render_expr(item.key),
            doc.text("] = "),
            render_expr(item.value),
        }
    )
end

local function build_table_item_docs(node: parser.Node): {TableItemDoc}
    local result: {TableItemDoc} = {}

    local previous_item: TableItemDoc | nil = nil

    local function comment_after_prev_item(comment: parser.Comment): TableItemDoc | nil
        if previous_item is nil then
            return nil
        end

        local previous_item_line = render_builders.node_end_line(previous_item.item)
        if previous_item_line == comment.y then
            return previous_item
        end

        return nil
    end

    local function append_comments(comments: {parser.Comment})
        for _, comment in ipairs(comments) do
            local attached_to_item = comment_after_prev_item(comment)
            if not (attached_to_item is nil) then
                attached_to_item.comment = comment
            else
                table.insert(result, TableItemDoc.new(nil, comment))
            end
        end
    end

    for _, item in ipairs(node) do
        append_comments(item.comments or {})
        local table_item_doc = TableItemDoc.new(item, nil)
        table.insert(result, table_item_doc)
        previous_item = table_item_doc
    end

    append_comments(node.end_comments or {})

    return result
end

local function build_delimited_sequence_doc(
    table_items: {TableItemDoc},
    render_expr: function(parser.Node): doc.Doc,
    opts: render_builders.DelimitedSequenceOptions,
    force_wrap: boolean
): doc.Doc
    local lines: {doc.Doc} = {}
    local table_have_comments = false
    for i, table_item in ipairs(table_items) do
        if table_item.item then
            table.insert(lines, build_table_item_text(table_item.item, render_expr))
            if i ~= #table_items or force_wrap then
                table.insert(lines, doc.text(", "))
            else
                table.insert(lines, doc.if_wrapped(", "))
            end
        end
        if table_item.comment then
            table.insert(lines, doc.text(table_item.comment.text))
            table_have_comments = true
        end

        if i < #table_items then
            if table_item.comment then
                table.insert(lines, doc.hardline())
            elseif force_wrap then
                table.insert(lines, doc.hardline())
            else
                table.insert(lines, doc.softline())
            end
        end
    end

    local items_doc = doc.concat(lines)
    if not (force_wrap or table_have_comments) then
        items_doc = doc.group(items_doc)
    end
    local talbe_doc = doc.concat(
        {
            doc.text(opts.open_delim),
            doc.indent(
                opts.compact_indent_amount,
                doc.concat(
                    {
                        force_wrap and doc.hardline() or doc.softline(),
                        items_doc,
                    }
                )
            ),
            force_wrap and doc.hardline() or doc.softline(),
            doc.text(opts.close_delim),
        }
    )
    if force_wrap or table_have_comments then
        return doc.concat({doc.break_parent(), talbe_doc})
    else
        return doc.group(talbe_doc)
    end
end

function table_doc.build_table_doc(
    node: parser.Node, render_expr: function(parser.Node): doc.Doc
): doc.Doc
    local opts = render_builders.DelimitedSequenceOptions.new("{", "}", 4)
    return build_delimited_sequence_doc(
        build_table_item_docs(node), render_expr, opts, node.trailing_comma
    )
end

return table_doc
