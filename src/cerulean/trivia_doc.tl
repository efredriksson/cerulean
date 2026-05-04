-- Rendering helpers for *_trivia node fields. One module so the three
-- consumers (expr_doc, table_doc, inline_stmt_doc) can't drift apart.
local doc = require("cerulean.doc")
local parser = require("cerulean.parser")

local trivia_doc = {}

-- A same-line entry only ever sits at index 1 (parser invariant), so we
-- check just the head — searching the whole list would mistake a later
-- own-line comment for a same-line one.
function trivia_doc.partition(
    trivia: {parser.Comment}, anchor_line: integer
): parser.Comment, {parser.Comment}
    local same_line: parser.Comment = nil
    local off_line: {parser.Comment} = {}
    if trivia == nil then
        return same_line, off_line
    end
    for index, c in ipairs(trivia) do
        if index == 1 and c.y == anchor_line then
            same_line = c
        else
            table.insert(off_line, c)
        end
    end
    return same_line, off_line
end

-- Use when own-line entries can't occur (e.g. before a separator).
function trivia_doc.append_inline(parts: {doc.Doc}, trivia: {parser.Comment})
    if trivia == nil then
        return
    end
    for _, c in ipairs(trivia) do
        table.insert(parts, doc.text(" " .. c.text))
    end
end

-- Like append_inline but joins with single spaces and emits no leading
-- space — for callers whose prefix already ends with whitespace or
-- where the trivia must sit flush against an opener like `(`.
function trivia_doc.append_inline_joined(parts: {doc.Doc}, trivia: {parser.Comment})
    for index, c in ipairs(trivia) do
        if index > 1 then
            table.insert(parts, doc.text(" "))
        end
        table.insert(parts, doc.text(c.text))
    end
end

-- Use at boundaries (e.g. operator) where any own-line entry must force
-- a break before the next chunk.
function trivia_doc.emit_transition(
    parts: {doc.Doc},
    trivia: {parser.Comment},
    anchor_line: integer,
    next_doc: doc.Doc,
    plain_separator: doc.Doc
)
    local same_line, off_line = trivia_doc.partition(trivia, anchor_line)
    if same_line then
        table.insert(parts, doc.text(" " .. same_line.text))
    end
    for _, c in ipairs(off_line) do
        table.insert(parts, doc.indent_hardline(doc.text(c.text)))
    end
    if same_line ~= nil or #off_line > 0 then
        table.insert(parts, doc.indent_hardline(next_doc))
    else
        table.insert(parts, plain_separator)
        table.insert(parts, next_doc)
    end
end

return trivia_doc
