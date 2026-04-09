local doc = require("formatter.doc")
local parser = require("formatter.parser")

local record DelimitedSequenceOptions
    open_delim: string
    close_delim: string
    compact_indent_amount: integer
end

local record CommentLineItem
    item_doc: doc.Doc
    item_end_line: integer
    comments: {parser.Comment}
    preserve_blank_line_after: boolean
end

local record CommentLineItems
    items: {CommentLineItem}
    end_comments: {parser.Comment}
    prefixed_comments: {parser.Comment}
    has_comments: boolean
end

local record LineEntry
    item_doc: doc.Doc | nil
    item_end_line: integer | nil
    leading_comments: {parser.Comment}
    trailing_comments: {parser.Comment}
    standalone_comment: parser.Comment | nil
    preserve_blank_line_after: boolean
    is_item: boolean
    is_comment_only: boolean
    has_leading_comments: boolean
    has_trailing_comments: boolean
    has_standalone_comment: boolean
    has_any_comments: boolean
    first_emitted_comment: parser.Comment | nil
    starts_with_blank_line: boolean
end

local record EntrySeparatorContext
    previous: LineEntry
    next: LineEntry
    previous_is_item: boolean
    next_is_item: boolean
    previous_has_trailing_comments: boolean
    next_has_leading_comments: boolean
    next_is_comment_only: boolean
    next_starts_with_blank_line: boolean
    previous_preserve_blank_line_after: boolean
end

local render_builders = {
    DelimitedSequenceOptions = DelimitedSequenceOptions,
    CommentLineItem = CommentLineItem,
    CommentLineItems = CommentLineItems,
    LineEntry = LineEntry,
    EntrySeparatorContext = EntrySeparatorContext,
}

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

function CommentLineItem.new(
    item_doc: doc.Doc,
    item_end_line: integer,
    comments: {parser.Comment},
    preserve_blank_line_after: boolean
): CommentLineItem
    local self: CommentLineItem = setmetatable({}, {__index = CommentLineItem})
    self.item_doc = item_doc
    self.item_end_line = item_end_line
    self.comments = comments
    self.preserve_blank_line_after = preserve_blank_line_after
    return self
end

function CommentLineItems.new(): CommentLineItems
    local self: CommentLineItems = setmetatable({}, {__index = CommentLineItems})
    self.items = {}
    self.end_comments = {}
    self.prefixed_comments = {}
    self.has_comments = false
    return self
end

function CommentLineItems:add(
    item_doc: doc.Doc,
    item_end_line: integer,
    comments: {parser.Comment},
    preserve_blank_line_after: boolean
)
    if #comments > 0 then
        self.has_comments = true
    end
    table.insert(
        self.items,
        CommentLineItem.new(
            item_doc, item_end_line, comments, preserve_blank_line_after
        )
    )
end

function CommentLineItems:mark_comments(comments: {parser.Comment})
    if #comments > 0 then
        self.has_comments = true
    end
end

function CommentLineItems:add_end_comments(comments: {parser.Comment})
    if #comments > 0 then
        self.has_comments = true
    end
    for _, comment in ipairs(comments) do
        table.insert(self.end_comments, comment)
    end
end

function CommentLineItems:add_prefixed_comments(comments: {parser.Comment})
    if #comments > 0 then
        self.has_comments = true
    end
    for _, comment in ipairs(comments) do
        table.insert(self.prefixed_comments, comment)
    end
end

function LineEntry.new(
    item_doc: doc.Doc | nil,
    item_end_line: integer | nil,
    leading_comments: {parser.Comment},
    trailing_comments: {parser.Comment},
    standalone_comment: parser.Comment | nil,
    preserve_blank_line_after: boolean
): LineEntry
    local self: LineEntry = setmetatable({}, {__index = LineEntry})
    self.item_doc = item_doc
    self.item_end_line = item_end_line
    self.leading_comments = leading_comments
    self.trailing_comments = trailing_comments
    self.standalone_comment = standalone_comment
    self.preserve_blank_line_after = preserve_blank_line_after
    self.is_item = false
    self.is_comment_only = false
    self.has_leading_comments = false
    self.has_trailing_comments = false
    self.has_standalone_comment = false
    self.has_any_comments = false
    self.first_emitted_comment = nil
    self.starts_with_blank_line = false
    return self
end

function EntrySeparatorContext.new(
    previous: LineEntry, next_entry: LineEntry
): EntrySeparatorContext
    local self: EntrySeparatorContext = setmetatable(
        {}, {__index = EntrySeparatorContext}
    )
    self.previous = previous
    self.next = next_entry
    self.previous_is_item = previous.is_item
    self.next_is_item = next_entry.is_item
    self.previous_has_trailing_comments = previous.has_trailing_comments
    self.next_has_leading_comments = next_entry.has_leading_comments
    self.next_is_comment_only = next_entry.is_comment_only
    self.next_starts_with_blank_line = next_entry.starts_with_blank_line
    self.previous_preserve_blank_line_after = previous.preserve_blank_line_after
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
    nodes: {parser.Node}, render_node: function(parser.Node): doc.Doc
): doc.Doc
    local item_docs: {doc.Doc} = {}
    for _, node in ipairs(nodes) do
        table.insert(item_docs, render_node(node))
    end
    return render_builders.build_comma_separated_docs(item_docs)
end

function render_builders.build_delimited_body_doc(
    items_doc: doc.Doc, opts: DelimitedSequenceOptions, line_doc: doc.Doc
): doc.Doc
    return doc.concat(
        {
            doc.text(opts.open_delim),
            doc.indent(
                opts.compact_indent_amount,
                doc.concat(
                    {
                        line_doc,
                        items_doc,
                    }
                )
            ),
            line_doc,
            doc.text(opts.close_delim),
        }
    )
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

function render_builders.node_effective_end_line(node: parser.Node): integer
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

function render_builders.statement_effective_end_line(stmt: parser.Node): integer
    local end_line = render_builders.node_effective_end_line(stmt)

    if stmt.exps ~= nil then
        for _, exp in ipairs(stmt.exps) do
            local exp_end_line = render_builders.node_effective_end_line(exp)
            if exp_end_line > end_line then
                end_line = exp_end_line
            end
        end
    end

    return end_line
end

function render_builders.call_arg_effective_end_line(node: parser.Node): integer
    return render_builders.node_effective_end_line(node)
end

function render_builders.build_comment_line_entries(
    line_items: CommentLineItems
): {LineEntry}
    local function update_line_entry_metadata(entry: LineEntry)
        local entry_item_doc = entry.item_doc
        local standalone_comment = entry.standalone_comment
        entry.is_item = not (entry_item_doc is nil)
        entry.has_leading_comments = #entry.leading_comments > 0
        entry.has_trailing_comments = #entry.trailing_comments > 0
        entry.has_standalone_comment = not (standalone_comment is nil)
        entry.has_any_comments = entry.has_leading_comments
            or entry.has_trailing_comments
            or entry.has_standalone_comment
        if entry.has_leading_comments then
            entry.first_emitted_comment = entry.leading_comments[1]
        else
            entry.first_emitted_comment = standalone_comment
        end
        local first_comment = entry.first_emitted_comment
        entry.starts_with_blank_line = not (first_comment is nil)
            and first_comment.blank_line_before == true
        entry.is_comment_only = not entry.is_item and entry.has_any_comments
    end

    local entries: {LineEntry} = {}
    local previous_entry: LineEntry | nil = nil
    local previous_end_line: integer | nil = nil

    local function maybe_with_inferred_blank_line_before(
        comment: parser.Comment, reference_line: integer
    ): parser.Comment
        if comment.blank_line_before == true or comment.y <= reference_line + 1 then
            return comment
        end

        return {
            y = comment.y,
            x = comment.x,
            text = comment.text,
            blank_line_before = true,
        }
    end

    local function attach_comment(
        comment: parser.Comment,
        next_entry: LineEntry | nil,
        infer_blank_line_before_from_gap: boolean,
        blank_line_reference_line: integer | nil
    )
        if not (previous_entry is nil) and not (previous_end_line is nil) then
            local non_nil_previous_end_line = previous_end_line
            if comment.y <= non_nil_previous_end_line then
                table.insert(previous_entry.trailing_comments, comment)
                return
            end
        end

        local attached_comment = comment
        if infer_blank_line_before_from_gap then
            local reference_line = 0
            if not (blank_line_reference_line is nil) then
                reference_line = blank_line_reference_line
            elseif not (previous_end_line is nil) then
                reference_line = previous_end_line
            end
            attached_comment = maybe_with_inferred_blank_line_before(
                comment, reference_line
            )
        end

        if not (next_entry is nil) then
            table.insert(next_entry.leading_comments, attached_comment)
        else
            table.insert(
                entries, LineEntry.new(nil, nil, {}, {}, attached_comment, false)
            )
        end
    end

    for _, item in ipairs(line_items.items) do
        local entry = LineEntry.new(
            item.item_doc,
            item.item_end_line,
            {},
            {},
            nil,
            item.preserve_blank_line_after
        )

        for _, comment in ipairs(item.comments) do
            attach_comment(comment, entry, false, nil)
        end

        table.insert(entries, entry)
        previous_entry = entry
        previous_end_line = item.item_end_line
    end

    local end_comment_reference_line = 0
    if not (previous_end_line is nil) then
        end_comment_reference_line = previous_end_line
    end
    for _, comment in ipairs(line_items.end_comments) do
        attach_comment(comment, nil, true, end_comment_reference_line)
        end_comment_reference_line = comment.y
    end

    for _, entry in ipairs(entries) do
        update_line_entry_metadata(entry)
    end

    return entries
end

local type BuildItemSuffix = function(LineEntry, boolean): doc.Doc
local type BuildEntrySeparator = function(EntrySeparatorContext): doc.Doc

function render_builders.default_entry_separator(_ctx: EntrySeparatorContext): doc.Doc
    return doc.line()
end

local function comment_has_blank_line_before(comment: parser.Comment): boolean
    return comment.blank_line_before == true
end

function render_builders.render_line_entries(
    line_items: CommentLineItems,
    build_item_suffix: BuildItemSuffix | nil,
    build_entry_separator: BuildEntrySeparator | nil
): doc.Doc
    local function update_line_entry_metadata(entry: LineEntry)
        local entry_item_doc = entry.item_doc
        local standalone_comment = entry.standalone_comment
        entry.is_item = not (entry_item_doc is nil)
        entry.has_leading_comments = #entry.leading_comments > 0
        entry.has_trailing_comments = #entry.trailing_comments > 0
        entry.has_standalone_comment = not (standalone_comment is nil)
        entry.has_any_comments = entry.has_leading_comments
            or entry.has_trailing_comments
            or entry.has_standalone_comment
        if entry.has_leading_comments then
            entry.first_emitted_comment = entry.leading_comments[1]
        else
            entry.first_emitted_comment = standalone_comment
        end
        local first_comment = entry.first_emitted_comment
        entry.starts_with_blank_line = not (first_comment is nil)
            and first_comment.blank_line_before == true
        entry.is_comment_only = not entry.is_item and entry.has_any_comments
    end

    local function default_build_item_suffix(_1: LineEntry, _2: boolean): doc.Doc
        return doc.text("")
    end

    local function default_build_entry_separator(ctx: EntrySeparatorContext): doc.Doc
        return render_builders.default_entry_separator(ctx)
    end

    local non_nil_build_item_suffix: BuildItemSuffix
    if build_item_suffix == nil then
        non_nil_build_item_suffix = default_build_item_suffix
    else
        non_nil_build_item_suffix = build_item_suffix
    end

    local non_nil_build_entry_separator: BuildEntrySeparator
    if build_entry_separator == nil then
        non_nil_build_entry_separator = default_build_entry_separator
    else
        non_nil_build_entry_separator = build_entry_separator
    end

    local entries = render_builders.build_comment_line_entries(line_items)
    if #line_items.prefixed_comments > 0 then
        local prefixed_entries: {LineEntry} = {}
        for _, comment in ipairs(line_items.prefixed_comments) do
            local prefixed_entry = LineEntry.new(nil, nil, {}, {}, comment, false)
            update_line_entry_metadata(prefixed_entry)
            table.insert(prefixed_entries, prefixed_entry)
        end
        for _, entry in ipairs(entries) do
            table.insert(prefixed_entries, entry)
        end
        entries = prefixed_entries
    end

    local item_count = 0
    for _, entry in ipairs(entries) do
        local entry_item_doc = entry.item_doc
        if not (entry_item_doc is nil) then
            item_count = item_count + 1
        end
    end

    local parts: {doc.Doc} = {}
    local item_index = 0
    local entry_initial_blank_line_consumed: {boolean} = {}

    local function append_comment_block(
        comments: {parser.Comment}, consume_initial_blank_line: boolean
    )
        for comment_index, comment in ipairs(comments) do
            if comment_index > 1 then
                table.insert(parts, doc.hardline())
                if comment_has_blank_line_before(comment) then
                    table.insert(parts, doc.hardline())
                end
            elseif comment_has_blank_line_before(comment)
                and not consume_initial_blank_line then
                table.insert(parts, doc.hardline())
            end
            table.insert(parts, doc.text(comment.text))
        end
    end

    for index, entry in ipairs(entries) do
        local entry_item_doc = entry.item_doc
        if #entry.leading_comments > 0 then
            append_comment_block(
                entry.leading_comments, entry_initial_blank_line_consumed[index] == true
            )
            if not (entry_item_doc is nil) then
                table.insert(parts, doc.hardline())
            end
        end

        local standalone_comment = entry.standalone_comment
        if not (standalone_comment is nil) then
            if comment_has_blank_line_before(standalone_comment)
                and not (entry_initial_blank_line_consumed[index] == true) then
                table.insert(parts, doc.hardline())
            end
            table.insert(parts, doc.text(standalone_comment.text))
        end

        if not (entry_item_doc is nil) then
            item_index = item_index + 1
            table.insert(parts, entry_item_doc)

            local suffix = non_nil_build_item_suffix(entry, item_index == item_count)
            if not (suffix is nil) then
                table.insert(parts, suffix)
            end

            if #entry.trailing_comments > 0 then
                for _, comment in ipairs(entry.trailing_comments) do
                    table.insert(parts, doc.text(" " .. comment.text))
                end
            end
        end

        if index < #entries then
            local next_entry = entries[index + 1]
            local separator = non_nil_build_entry_separator(
                EntrySeparatorContext.new(entry, next_entry)
            )
            table.insert(parts, separator)
            local next_first_comment = next_entry.first_emitted_comment
            if not (next_first_comment is nil)
                and comment_has_blank_line_before(next_first_comment) then
                table.insert(parts, doc.hardline())
                entry_initial_blank_line_consumed[index + 1] = true
            end
        end
    end

    return doc.concat(parts)
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

return render_builders
