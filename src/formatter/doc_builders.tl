local doc = require("formatter.doc")

local record DelimitedSequenceOptions
    open_delim: string
    close_delim: string
    compact_indent_amount: integer
    trailing_break_separator: boolean
end

local doc_builders = {
    DelimitedSequenceOptions = DelimitedSequenceOptions,
}

function DelimitedSequenceOptions.new(
    open_delim: string,
    close_delim: string,
    compact_indent_amount: integer,
    trailing_break_separator: boolean
): DelimitedSequenceOptions
    local self: DelimitedSequenceOptions = setmetatable(
        {}, { __index = DelimitedSequenceOptions }
    )
    self.open_delim = open_delim
    self.close_delim = close_delim
    self.compact_indent_amount = compact_indent_amount
    self.trailing_break_separator = trailing_break_separator
    return self
end

local function build_item_docs(
    items: {string}, trailing_break_separator: boolean
): {doc.Doc}
    local item_docs: {doc.Doc} = {}
    for i, item in ipairs(items) do
        local item_parts: {doc.Doc} = {
            doc.text(item),
        }
        if i < #items then
            table.insert(item_parts, doc.text(","))
            table.insert(item_parts, doc.line(" "))
        elseif trailing_break_separator then
            table.insert(item_parts, doc.break_text(","))
        end
        table.insert(item_docs, doc.concat(item_parts))
    end
    return item_docs
end

function doc_builders.render_delimited_sequence(
    items: {string}, indent_prefix: string, opts: DelimitedSequenceOptions
): {string}
    if #items < 2 then
        return {
            opts.open_delim .. table.concat(items, ", ") .. opts.close_delim,
        }
    end

    local sequence_doc = doc.concat({
        doc.text(opts.open_delim),
        doc.indent(opts.compact_indent_amount, doc.concat({
            doc.line(""),
            doc.group(doc.concat(build_item_docs(
               items, opts.trailing_break_separator
            ))),
        })),
        doc.line(""),
        doc.text(opts.close_delim),
    })

    return sequence_doc:render(88, 0, #indent_prefix, true)
end

local function render_expanded_delimited_sequence(
    items: {string}, indent_prefix: string, opts: DelimitedSequenceOptions
): {string}
    if #items < 2 then
        return {
            opts.open_delim .. table.concat(items, ", ") .. opts.close_delim,
        }
    end

    local sequence_doc = doc.concat({
        doc.text(opts.open_delim),
        doc.indent(opts.compact_indent_amount, doc.concat({
            doc.line(""),
            doc.concat(build_item_docs(items, opts.trailing_break_separator)),
        })),
        doc.line(""),
        doc.text(opts.close_delim),
    })

    return sequence_doc:render(88, 0, #indent_prefix, true)
end

function doc_builders.render_trailing_call_sequence(
    items: {string}, indent_prefix: string, fallback_opts: DelimitedSequenceOptions
): {string}
    if #items < 2 then
        return {
            fallback_opts.open_delim .. table.concat(
               items, ", "
            ) .. fallback_opts.close_delim,
        }
    end

    local compact_doc = doc.concat({
        doc.text("("),
        doc.indent(3, doc.concat({
            doc.line(""),
            doc.text(table.concat(items, ", ")),
        })),
        doc.line(""),
        doc.text(")"),
    })
    local compact_lines = compact_doc:render(88, 0, #indent_prefix, true)
    if #compact_lines == 3 and #compact_lines[2] <= 88 then
        return compact_lines
    end

    return doc_builders.render_delimited_sequence(items, indent_prefix, fallback_opts)
end

local function wrap_construct_lines(
    prefix: string, suffix: string, lines: {string}
): {string}
    local result: {string} = {}
    for i, line_str in ipairs(lines) do
        if i == 1 then
            table.insert(result, prefix .. line_str)
        elseif i == #lines then
            table.insert(result, line_str .. suffix)
        else
            table.insert(result, line_str)
        end
    end
    return result
end

local function extract_items_from_span(
    span_content: string, split_items: function(string): {string}
): {string}
    local inner = span_content:sub(2, -2)
    inner = inner:match("^%s*(.-)%s*$") or ""
    return split_items(inner)
end

local function delimiters_for_kind(kind: string): string, string
    if kind == "table" then
        return "{", "}"
    end

    return "(", ")"
end

function doc_builders.extract_items_from_span_lines(
    kind: string, span_lines: {string}, split_items: function(string): {string}
): {string}
    local open_delim, close_delim = delimiters_for_kind(kind)
    local stripped_lines: {string} = {}

    for i, span_line in ipairs(span_lines) do
        local stripped = span_line:match("^%s*(.-)%s*$") or ""
        if i == 1 then
            if stripped:sub(1, 1) ~= open_delim then
                return split_items(table.concat(span_lines, "\n"))
            end
            stripped = stripped:sub(2)
            stripped = stripped:match("^%s*(.-)%s*$") or ""
        end
        if i == #span_lines then
            stripped = stripped:gsub("%s*" .. "%" .. close_delim .. "%s*$", "")
            stripped = stripped:match("^%s*(.-)%s*$") or ""
        end
        table.insert(stripped_lines, stripped)
    end

    return split_items(table.concat(stripped_lines, "\n"))
end

function doc_builders.extract_items_from_span_content(
    span_content: string, split_items: function(string): {string}
): {string}
    return extract_items_from_span(span_content, split_items)
end

function doc_builders.compact_construct_text(kind: string, items: {string}): string
    local open_delim, close_delim = delimiters_for_kind(kind)
    return open_delim .. table.concat(items, ", ") .. close_delim
end

function doc_builders.render_construct(
    kind: string,
    prefix: string,
    items: {string},
    suffix: string,
    indent_prefix: string,
    prefer_trailing_compact: boolean
): {string}
    local sequence_opts: DelimitedSequenceOptions
    if kind == "table" then
        sequence_opts = DelimitedSequenceOptions.new("{", "}", 4, true)
    else
        sequence_opts = DelimitedSequenceOptions.new("(", ")", 4, false)
    end

    if #items < 2 then
        return {
            prefix
                .. sequence_opts.open_delim
                .. table.concat(items, ", ")
                .. sequence_opts.close_delim
                .. suffix,
        }
    end

    local lines: {string}
    if kind == "call" and prefer_trailing_compact then
        lines = doc_builders.render_trailing_call_sequence(
            items, indent_prefix, sequence_opts
        )
    elseif kind == "call" and suffix ~= "" then
        lines = render_expanded_delimited_sequence(items, indent_prefix, sequence_opts)
    else
        lines = doc_builders.render_delimited_sequence(
            items, indent_prefix, sequence_opts
        )
    end

    return wrap_construct_lines(prefix, suffix, lines)
end

return doc_builders
