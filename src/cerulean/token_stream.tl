-- The lossless token backbone. `tl.lex` recognizes Teal tokens and hands every
-- comment to the token that follows it, but leaves the comment-to-token
-- relationship implicit. This module splits each gap's comments into per-token
-- leading/trailing trivia by the same-line rule, so every comment the lexer
-- reports belongs to exactly one token and nothing commented can be silently
-- dropped. Positions are lines and columns throughout; whitespace between items
-- is re-derived by the Doc IR, never stored here.
local source = require("cerulean.source")
local tl = require("tl")

-- A comment carried as trivia on a token. `yend` is the line the comment text
-- ends on, precomputed here because extent reads walk trivia far more often than
-- trivia is lexed.
local record Trivia
    text: string
    y: integer
    x: integer
    yend: integer
    new: function(string, integer, integer): Trivia
end

-- One lexical token plus the comments that bind to it. `leading_trivia` are
-- own-line comments before the token; `trailing_trivia` are same-line comments
-- after it. `yend` is the line the token text ends on; end lines never decrease
-- with token index, which lets extent reads use a span's last token instead of
-- walking.
local record Token
    kind: tl.TokenKind
    text: string
    y: integer
    x: integer
    yend: integer
    leading_trivia: {Trivia}
    trailing_trivia: {Trivia}
    new: function(tl.TokenKind, string, integer, integer): Token
end

-- The token array plus its consume ledger. The ledger records which trivia the
-- render has already emitted, keyed by source position (line, then column --
-- unique per comment): a comment absent here was taken by no render slot, so
-- the per-statement sweep can relocate such strays and the audit can name what
-- a render lost.
local record Stream is {Token}
    consumed: {integer: {integer: boolean}}
end

local token_stream = {Token = Token, Trivia = Trivia, Stream = Stream}

function Stream.new(): Stream
    local self: Stream = setmetatable({}, {__index = Stream})
    self.consumed = {}
    return self
end

function Stream:mark_consumed(y: integer, x: integer)
    local row = self.consumed[y]
    if row == nil then
        row = {}
        self.consumed[y] = row
    end
    row[x] = true
end

function Stream:is_consumed(y: integer, x: integer): boolean
    local row = self.consumed[y]
    return row ~= nil and row[x] == true
end

local function consume_slice_side(
    self: Stream,
    trivia: {Trivia},
    first_line: integer,
    start_col: integer,
    last_line: integer,
    last_line_cut_col: integer | nil
)
    for k = 1, #trivia do
        local trivium = trivia[k]
        if trivium.y >= first_line and trivium.y <= last_line then
            local after_start = trivium.y > first_line or trivium.x >= start_col
            local before_cut = trivium.y < last_line
                or last_line_cut_col == nil
                or trivium.x < last_line_cut_col
            if after_start and before_cut then
                self:mark_consumed(trivium.y, trivium.x)
            end
        end
    end
end

-- Mark every trivium inside a source window consumed: whole lines
-- first_line..last_line, except that the first line starts at start_col and the
-- last line stops before last_line_cut_col (nil to take it whole). Used when a
-- caller has emitted a source slice raw, so its comments must not be emitted a
-- second time through the accessors or the sweep.
function Stream:consume_slice(
    first_line: integer,
    start_col: integer,
    last_line: integer,
    last_line_cut_col: integer | nil
)
    for index = 1, #self do
        local token = self[index]
        consume_slice_side(
            self,
            token.leading_trivia,
            first_line,
            start_col,
            last_line,
            last_line_cut_col
        )
        consume_slice_side(
            self,
            token.trailing_trivia,
            first_line,
            start_col,
            last_line,
            last_line_cut_col
        )
    end
end

local function take_unconsumed_side(
    self: Stream, trivia: {Trivia}, frozen: source.Regions, taken: {Trivia}
)
    for k = 1, #trivia do
        local trivium = trivia[k]
        if
            not self:is_consumed(trivium.y, trivium.x)
            and not frozen:includes_line(trivium.y)
        then
            self:mark_consumed(trivium.y, trivium.x)
            table.insert(taken, trivium)
        end
    end
end

-- Every trivium in the token index window [first, last] that no accessor consumed
-- and no fmt-off region froze (a frozen comment renders raw, never through the
-- ledger). Token-ascending, leading-before-trailing order is source order. Each
-- taken trivium is marked consumed: the caller owns emitting it, so an enclosing
-- scan skips it.
function Stream:take_unconsumed(
    first: integer, last: integer, frozen: source.Regions
): {Trivia}
    local taken: {Trivia} = {}
    for index = first, last do
        local token = self[index]
        take_unconsumed_side(self, token.leading_trivia, frozen, taken)
        take_unconsumed_side(self, token.trailing_trivia, frozen, taken)
    end
    return taken
end

local function newline_count(text: string): integer
    if not text:find("\n", 1, true) then
        return 0
    end
    local _, count = text:gsub("\n", "")
    return count
end

-- Shared empty trivia list for the common comment-less token, so lexing does not
-- allocate two tables per token. Never mutated: partition_comments swaps in a
-- fresh table before the first insert.
local EMPTY_TRIVIA: {Trivia} = {}

function Trivia.new(text: string, y: integer, x: integer): Trivia
    local self: Trivia = setmetatable({}, {__index = Trivia})
    self.text = text
    self.y = y
    self.x = x
    self.yend = y + newline_count(text)
    return self
end

function Token.new(kind: tl.TokenKind, text: string, y: integer, x: integer): Token
    local self: Token = setmetatable({}, {__index = Token})
    self.kind = kind
    self.text = text
    self.y = y
    self.x = x
    self.yend = y + newline_count(text)
    self.leading_trivia = EMPTY_TRIVIA
    self.trailing_trivia = EMPTY_TRIVIA
    return self
end

-- Shared empty stand-in for tokens with no comments, so the hot lex loop does not
-- allocate a fresh table per token. Never mutated.
local EMPTY_COMMENTS: {tl.LexerComment} = {}

-- The $EOF$ sentinel reports "$EOF$" as its tk but owns no source bytes; every
-- other token's text is verbatim. An empty-text EOF token still anchors any
-- file-trailing comments as its leading trivia.
local function token_text(item: tl.Token): string
    if item.kind == "$EOF$" then
        return ""
    end
    return item.tk
end

-- Splits the comments tl.lex parked on a token into trailing trivia of the
-- previous token (same line as where it ended) and leading trivia of the token
-- itself (own-line). Returns the leading list; trailing entries are appended
-- directly onto `prev`.
local function partition_comments(
    comments: {tl.LexerComment}, prev: Token, prev_end_y: integer
): {Trivia}
    if #comments == 0 then
        return EMPTY_TRIVIA
    end
    local leading: {Trivia} = {}
    for k = 1, #comments do
        local comment = comments[k]
        local trivia = Trivia.new(comment.text, comment.y, comment.x)
        if prev ~= nil and comment.y == prev_end_y then
            if prev.trailing_trivia == EMPTY_TRIVIA then
                prev.trailing_trivia = {}
            end
            table.insert(prev.trailing_trivia, trivia)
        else
            table.insert(leading, trivia)
        end
    end
    return leading
end

-- Builds the lossless stream from an already-lexed token array. The parser owns
-- the lex (parser.parse returns its token array, with the statement `;` tokens
-- it discarded removed and their comments moved to the next token), so a stream
-- built from that array is index-aligned with the node stamps by identity -- one
-- Token per array entry, same order. The final `$EOF$` token holds any
-- file-trailing comments so they too survive.
function token_stream.from_tokens(lexed: {tl.Token}): Stream
    local tokens = Stream.new()
    local prev_end_y = 0
    for index = 1, #lexed do
        local item = lexed[index]
        local prev = tokens[#tokens]
        local leading = partition_comments(
            item.comments or EMPTY_COMMENTS, prev, prev_end_y
        )
        local token = Token.new(item.kind, token_text(item), item.y, item.x)
        token.leading_trivia = leading
        tokens[#tokens + 1] = token
        prev_end_y = token.yend
    end
    return tokens
end

return token_stream
