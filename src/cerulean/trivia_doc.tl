-- Rendering helpers for *_trivia node fields. One module so the three
-- consumers (expr_doc, table_doc, inline_stmt_doc) can't drift apart.
local ast = require("cerulean.ast")
local doc = require("cerulean.doc")

local trivia_doc = {}

-- A block comment (`--[[ ]]`, `--[=[ ]=]`) can sit flush between two tokens on one
-- line; a line comment (`--`) runs to end of line, so anything after it must move
-- to the next line. emit_transition keys its inline-vs-break choice on this, and
-- render_context shares it to filter block-only inline slots (one definition, since
-- both modules classify the same comment text).
function trivia_doc.is_block_comment(text: string): boolean
    return text:sub(1, 4) == "--[[" or text:match("^%-%-%[=*%[") ~= nil
end

-- Turns a statement-level comment (own-line leading, a swept stray, or a statement
-- trailing) into a doc. A line comment runs to end of line, so it can never be
-- flat-safe: it carries break_parent, opening its nearest enclosing group so the
-- block separator (`; ` when that group is flat) after it renders as a real newline
-- instead of folding the next statement -- or a flattened function's `end` -- onto
-- the comment's line. A block comment may sit flush between tokens, so it stays plain
-- text. Only the statement-boundary emitters route here (append_comment_docs,
-- trailing_comment_doc); inline trivia inside a statement uses indent_hardline to
-- break locally and so cannot swallow, and need not force its whole group open.
function trivia_doc.comment_doc(comment: ast.Comment): doc.Doc
    if trivia_doc.is_block_comment(comment.text) then
        return doc.text(comment.text)
    end
    return doc.concat({doc.text(comment.text), doc.break_parent()})
end

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

-- Inline trivia with no pad — for callers whose prefix already ends in
-- whitespace or where the trivia must sit flush against an opener like `(`.
function trivia_doc.append_inline_joined(parts: {doc.Doc}, trivia: {ast.Comment})
    if #trivia > 0 then
        table.insert(parts, joined(trivia))
    end
end

-- Use at boundaries (e.g. operator) where any own-line entry must force a break
-- before the next chunk. With `inline_block`, a single same-line block comment is
-- kept flush and the next chunk continues on the same line (e.g. a cast's
-- `as --[[c]] T`); without it any same-line comment forces the break, the operator
-- default.
function trivia_doc.emit_transition(
    parts: {doc.Doc},
    trivia: {ast.Comment},
    anchor_line: integer,
    next_doc: doc.Doc,
    plain_separator: doc.Doc,
    inline_block?: boolean
)
    local same_line, off_line = trivia_doc.partition(trivia, anchor_line)
    -- A same-line block comment may sit flush and let the next chunk continue on
    -- the same line; a same-line line comment (runs to end of line) or any own-line
    -- comment forces the next chunk onto its own line.
    local same_line_inline = inline_block
        and same_line ~= nil
        and trivia_doc.is_block_comment(same_line.text)
    local forces_break = #off_line > 0 or (same_line ~= nil and not same_line_inline)
    if same_line ~= nil then
        table.insert(parts, doc.text(" " .. same_line.text))
    end
    for _, c in ipairs(off_line) do
        table.insert(parts, doc.indent_hardline(doc.text(c.text)))
    end
    if forces_break then
        table.insert(parts, doc.indent_hardline(next_doc))
    else
        table.insert(parts, plain_separator)
        table.insert(parts, next_doc)
    end
end

return trivia_doc
