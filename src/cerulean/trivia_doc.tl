-- Rendering helpers for *_trivia node fields. One module so the three
-- consumers (expr_doc, table_doc, inline_stmt_doc) can't drift apart.
local ast = require("cerulean.ast")
local doc = require("cerulean.doc")

local trivia_doc = {}

-- A same-line entry only ever sits at index 1 (parser invariant), so we
-- check just the head — searching the whole list would mistake a later
-- own-line comment for a same-line one.
function trivia_doc.partition(
    trivia: {ast.Comment}, anchor_line: integer
): ast.Comment, {ast.Comment}
    local same_line: ast.Comment = nil
    local off_line: {ast.Comment} = {}
    if trivia == nil then
        return same_line, off_line
    end
    for index, comment in ipairs(trivia) do
        if index == 1 and comment.y == anchor_line then
            same_line = comment
        else
            table.insert(off_line, comment)
        end
    end
    return same_line, off_line
end

-- The shared core of the inline emitters: the comment texts joined by a single
-- space, with no surrounding space. The three emitters below differ only in
-- which side gets a pad space facing the adjacent content.
local function joined(comments: {ast.Comment}): doc.Doc
    local parts: {doc.Doc} = {}
    for index, comment in ipairs(comments) do
        if index > 1 then
            table.insert(parts, doc.text(" "))
        end
        table.insert(parts, doc.text(comment.text))
    end
    return doc.concat(parts)
end

-- Trailing inline trivia: a pad space then the run, for comments that sit after
-- a value (e.g. before a separator). No-op when empty.
function trivia_doc.append_inline(parts: {doc.Doc}, trivia: {ast.Comment})
    if #trivia > 0 then
        table.insert(parts, doc.text(" "))
        table.insert(parts, joined(trivia))
    end
end

-- Leading inline trivia: the run then a pad space, so the element that follows
-- renders flush after the comments. No-op when empty.
function trivia_doc.append_leading(parts: {doc.Doc}, leading: {ast.Comment})
    if #leading > 0 then
        table.insert(parts, joined(leading))
        table.insert(parts, doc.text(" "))
    end
end

-- Inline trivia with no pad — for callers whose prefix already ends in
-- whitespace or where the trivia must sit flush against an opener like `(`.
function trivia_doc.append_inline_joined(parts: {doc.Doc}, trivia: {ast.Comment})
    if #trivia > 0 then
        table.insert(parts, joined(trivia))
    end
end

-- Wraps an element with its inline block comments, space-separated: `leading`
-- before it, `trailing` after it.
function trivia_doc.wrap_element(
    element: doc.Doc, leading: {ast.Comment}, trailing: {ast.Comment}
): doc.Doc
    local parts: {doc.Doc} = {}
    trivia_doc.append_leading(parts, leading)
    table.insert(parts, element)
    trivia_doc.append_inline(parts, trailing)
    return doc.concat(parts)
end

-- Use at boundaries (e.g. operator) where any own-line entry must force
-- a break before the next chunk.
function trivia_doc.emit_transition(
    parts: {doc.Doc},
    trivia: {ast.Comment},
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
