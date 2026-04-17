local doc = require("formatter.doc")
local parser = require("formatter.parser")

local record DelimitedSequenceOptions
    open_delim: string
    close_delim: string
end

local record CommentLineItem
    item_doc: doc.Doc
    item_end_line: integer
    item_start_line: integer | nil
    blank_line_before: boolean
    blank_line_after_leading_comments: boolean
    raw_comments: {parser.Comment} | nil
    preserve_blank_line_after: boolean
end

local record CommentLineItems
    items: {CommentLineItem}
    end_comments: {parser.Comment}
    has_comments: boolean
end

local record LineEntry
    item_doc: doc.Doc | nil
    item_end_line: integer | nil
    leading_comments: {parser.Comment}
    trailing_comments: {parser.Comment}
    blank_line_before: boolean
    blank_line_after_leading_comments: boolean
    preserve_blank_line_after: boolean
    is_item: boolean
    is_comment_only: boolean
    has_leading_comments: boolean
    has_any_comments: boolean
end

local record EntrySeparatorContext
    previous: LineEntry
    next: LineEntry
    previous_is_item: boolean
    next_is_item: boolean
    next_has_leading_comments: boolean
    next_is_comment_only: boolean
end

local render_builders = {
    DelimitedSequenceOptions = DelimitedSequenceOptions,
    CommentLineItem = CommentLineItem,
    CommentLineItems = CommentLineItems,
    LineEntry = LineEntry,
    EntrySeparatorContext = EntrySeparatorContext,
}

function render_builders.node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function statement_effective_end_line(stmt: parser.Node): integer
    return stmt.yend or stmt.y
end

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

function CommentLineItem.new(
    item_doc: doc.Doc,
    item_end_line: integer,
    item_start_line: integer,
    comments: {parser.Comment},
    preserve_blank_line_after: boolean
): CommentLineItem
    local self: CommentLineItem = setmetatable({}, {__index = CommentLineItem})
    self.item_doc = item_doc
    self.item_end_line = item_end_line
    self.item_start_line = item_start_line
    self.blank_line_before = false
    self.blank_line_after_leading_comments = false
    self.raw_comments = comments
    self.preserve_blank_line_after = preserve_blank_line_after
    return self
end

function CommentLineItems.new(): CommentLineItems
    local self: CommentLineItems = setmetatable({}, {__index = CommentLineItems})
    self.items = {}
    self.end_comments = {}
    self.has_comments = false
    return self
end

function CommentLineItems:add(
    item_doc: doc.Doc,
    node: parser.Node,
    comments: {parser.Comment},
    preserve_blank_line_after: boolean
)
    if #comments > 0 then
        self.has_comments = true
    end
    table.insert(
        self.items,
        CommentLineItem.new(
            item_doc,
            statement_effective_end_line(node),
            node.y,
            comments,
            preserve_blank_line_after
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

function LineEntry.new(
    item_doc: doc.Doc | nil,
    item_end_line: integer | nil,
    blank_line_before: boolean,
    blank_line_after_leading_comments: boolean
): LineEntry
    local self: LineEntry = setmetatable({}, {__index = LineEntry})
    self.item_doc = item_doc
    self.item_end_line = item_end_line
    self.leading_comments = {}
    self.trailing_comments = {}
    self.blank_line_before = blank_line_before
    self.blank_line_after_leading_comments = blank_line_after_leading_comments
    self.preserve_blank_line_after = false
    self.is_item = false
    self.is_comment_only = false
    self.has_leading_comments = false
    self.has_any_comments = false
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
    self.next_has_leading_comments = next_entry.has_leading_comments
    self.next_is_comment_only = next_entry.is_comment_only
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
            doc.indent(doc.concat({line_doc, items_doc})),
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

function render_builders.call_arg_effective_end_line(node: parser.Node): integer
    return render_builders.node_end_line(node)
end

local function update_line_entry_metadata(entry: LineEntry)
    local item_doc = entry.item_doc
    entry.is_item = not (item_doc is nil)
    entry.has_leading_comments = #entry.leading_comments > 0
    entry.is_comment_only = not entry.is_item and entry.has_leading_comments
    entry.has_any_comments = entry.has_leading_comments or #entry.trailing_comments > 0
end

function render_builders.build_comment_line_entries(
    line_items: CommentLineItems
): {LineEntry}
    local entries: {LineEntry} = {}
    local previous_entry: LineEntry | nil = nil
    local previous_end_line: integer | nil = nil

    -- Legacy classification: attach a comment to the previous entry (trailing)
    -- or the next entry (leading), or create a standalone entry.
    local function attach_comment_legacy(
        comment: parser.Comment, next_entry: LineEntry | nil
    )
        if not (previous_entry is nil) and not (previous_end_line is nil) then
            if comment.y <= previous_end_line then
                table.insert(previous_entry.trailing_comments, comment)
                return
            end
        end

        if not (next_entry is nil) then
            table.insert(next_entry.leading_comments, comment)
        else
            local standalone = LineEntry.new(nil, nil, comment.blank_line_before, false)
            table.insert(standalone.leading_comments, comment)
            update_line_entry_metadata(standalone)
            table.insert(entries, standalone)
        end
    end

    for _, item in ipairs(line_items.items) do
        local entry = LineEntry.new(item.item_doc, item.item_end_line, false, false)
        entry.preserve_blank_line_after = item.preserve_blank_line_after

        local raw_comments = item.raw_comments
        if not (raw_comments is nil) then
            for _, comment in ipairs(raw_comments) do
                attach_comment_legacy(comment, entry)
            end
        end

        if #entry.leading_comments > 0 then
            entry.blank_line_before = entry.leading_comments[1].blank_line_before
        end

        local item_start = item.item_start_line
        if #entry.leading_comments > 0 and not (item_start is nil) then
            local last_leading = entry.leading_comments[#entry.leading_comments]
            local last_comment_end = last_leading.yend or last_leading.y
            if last_comment_end < item_start - 1 then
                entry.blank_line_after_leading_comments = true
            end
        end

        update_line_entry_metadata(entry)
        table.insert(entries, entry)
        previous_entry = entry
        previous_end_line = item.item_end_line
    end

    for _, comment in ipairs(line_items.end_comments) do
        attach_comment_legacy(comment, nil)
    end

    return entries
end

local type BuildItemSuffix = function(LineEntry, boolean): doc.Doc
local type BuildEntrySeparator = function(EntrySeparatorContext): doc.Doc

function render_builders.default_entry_separator(_ctx: EntrySeparatorContext): doc.Doc
    return doc.line()
end

function render_builders.render_line_entries(
    line_items: CommentLineItems,
    build_item_suffix: BuildItemSuffix | nil,
    build_entry_separator: BuildEntrySeparator | nil
): doc.Doc
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

    local item_count = 0
    for _, entry in ipairs(entries) do
        local entry_item_doc_check = entry.item_doc
        if not (entry_item_doc_check is nil) then
            item_count = item_count + 1
        end
    end

    local parts: {doc.Doc} = {}
    local item_index = 0

    for index, entry in ipairs(entries) do
        -- Separator between entries (hardline by default; callers may customise).
        if index > 1 then
            local prev_entry = entries[index - 1]
            local separator = non_nil_build_entry_separator(
                EntrySeparatorContext.new(prev_entry, entry)
            )
            table.insert(parts, separator)
        end

        -- Blank line before this entry (applies to the first leading comment or
        -- the statement itself when there are no leading comments).
        if entry.blank_line_before then
            table.insert(parts, doc.hardline())
        end

        -- Leading comments, each on its own line, preserving internal blank lines.
        for comment_index, comment in ipairs(entry.leading_comments) do
            if comment_index > 1 then
                table.insert(parts, doc.hardline())
                if comment.blank_line_before then
                    table.insert(parts, doc.hardline())
                end
            end
            table.insert(parts, doc.text(comment.text))
        end

        -- Gap between leading comments and the statement body, when present.
        if entry.has_leading_comments then
            if entry.blank_line_after_leading_comments then
                table.insert(parts, doc.hardline())
            end
            local item_doc_check = entry.item_doc
            if not (item_doc_check is nil) then
                table.insert(parts, doc.hardline())
            end
        end

        -- Statement body.
        local entry_item_doc = entry.item_doc
        if not (entry_item_doc is nil) then
            item_index = item_index + 1
            table.insert(parts, entry_item_doc)

            local suffix = non_nil_build_item_suffix(entry, item_index == item_count)
            if not (suffix is nil) then
                table.insert(parts, suffix)
            end
        end

        -- Trailing inline comments (same line as the statement).
        for _, comment in ipairs(entry.trailing_comments) do
            table.insert(parts, doc.text(" " .. comment.text))
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
