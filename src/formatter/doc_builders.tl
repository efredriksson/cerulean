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

function doc_builders.render_function_signature(
    prefix: string, params: {string}, suffix: string, indent_prefix: string
): {string}
    if #params < 2 then
        return {
            prefix .. "(" .. table.concat(params, ", ") .. ")" .. suffix,
        }
    end

    local sequence_opts = DelimitedSequenceOptions.new("(", ")", 4, false)
    local param_lines = doc_builders.render_delimited_sequence(
        params, indent_prefix, sequence_opts
    )

    local result: {string} = {}
    for i, line_str in ipairs(param_lines) do
        if i == 1 then
            table.insert(result, prefix .. line_str)
        elseif i == #param_lines then
            table.insert(result, line_str .. suffix)
        else
            table.insert(result, line_str)
        end
    end
    return result
end

function doc_builders.render_table_constructor(
    prefix: string, fields: {string}, suffix: string, indent_prefix: string
): {string}
    if #fields < 2 then
        return {
            prefix .. "{" .. table.concat(fields, ", ") .. "}" .. suffix,
        }
    end

    local sequence_opts = DelimitedSequenceOptions.new("{", "}", 4, true)
    local field_lines = doc_builders.render_delimited_sequence(
        fields, indent_prefix, sequence_opts
    )

    local result: {string} = {}
    for i, line_str in ipairs(field_lines) do
        if i == 1 then
            table.insert(result, prefix .. line_str)
        elseif i == #field_lines then
            table.insert(result, line_str .. suffix)
        else
            table.insert(result, line_str)
        end
    end
    return result
end

return doc_builders
