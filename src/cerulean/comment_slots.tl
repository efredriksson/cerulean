-- A node's comment slots: the mapping from the parser's token-ownership stamps
-- (tok_first/tok_last/slot_tok/tok_op/tok_sep/tok_bound) to the comments each
-- render slot emits, marking every read on the stream's consume ledger. The
-- trivia loops here run hot; they use numeric `for` instead of `ipairs`, which
-- resolves to the compat53 shim under Lua 5.1 and profiled at a double-digit
-- share of a full rewrite.
local ast = require("cerulean.ast")
local source = require("cerulean.source")
local token_stream = require("cerulean.token_stream")
local trivia_doc = require("cerulean.trivia_doc")

local record CommentSlots
    -- The lossless token stream, index-aligned with the parser tokens that a
    -- node's tok_first/tok_last/slot_tok address. The slot reads take comment
    -- trivia straight off these tokens; the stream's consume ledger records what
    -- the render has already emitted.
    tokens: token_stream.Stream
    source_lines: {string}
    fmt_off_regions: source.Regions
    -- Leading comments that require_sort has authoritatively placed for the nodes
    -- it reordered (keyed by node). require_sort relocates comments contrary to
    -- source order -- module documentation to the top of the sorted block, a
    -- require's own comments travelling with it -- which the token stream, keyed
    -- on source position, cannot express. For a node listed here leading_comments
    -- reads this placement instead of the token stream; every other node reads
    -- its leading straight off its tokens.
    leading_overrides: {ast.Node: {ast.Comment}}
end

local comment_slots = {
    CommentSlots = CommentSlots,
}

function CommentSlots.new(
    tokens: token_stream.Stream,
    source_lines: {string},
    fmt_off_regions: source.Regions,
    leading_overrides: {ast.Node: {ast.Comment}}
): CommentSlots
    local self: CommentSlots = setmetatable({}, {__index = CommentSlots})
    self.tokens = tokens
    self.source_lines = source_lines
    self.fmt_off_regions = fmt_off_regions
    self.leading_overrides = leading_overrides
    return self
end

-- Shared empty result for the reads that find no comment, which is nearly all of
-- them: a whole-file render makes tens of thousands of slot reads and only a
-- fraction land on a comment. Callers iterate or take the length, never append,
-- so one table serves them all. Never mutated.
local EMPTY_COMMENTS: {ast.Comment} = {}

-- A blank separation is an actual blank source line in the open interval, not a
-- mere line-number gap: the parser deletes discarded `;` tokens, so a line that
-- held only a `;` sits inside a gap without being blank.
local function blank_line_between(
    self: CommentSlots, after: integer, before: integer
): boolean
    for line = after + 1, before - 1 do
        local text = self.source_lines[line]
        if text == nil or text:match("^%s*$") ~= nil then
            return true
        end
    end
    return false
end

-- Trivia and Comment share text/x/y; the renderer's emit helpers speak Comment,
-- so re-stamp each trivium with its derived end line. `prev_y` is the line the
-- preceding token sat on, for own-line runs (dangling/leading) that carry
-- blank_line_before: a comment leads with a blank line when a blank source line
-- separates it from what came before, measured first from the previous token and
-- then from each comment's own end. Pass nil for same-line (inline) runs, which
-- stay flush and never carry a blank line.
local function comments_from_trivia(
    self: CommentSlots, trivia: {token_stream.Trivia}, prev_y: integer | nil
): {ast.Comment}
    if #trivia == 0 then
        return EMPTY_COMMENTS
    end
    local comments: {ast.Comment} = {}
    for k = 1, #trivia do
        local item = trivia[k]
        table.insert(
            comments,
            {
                x = item.x,
                y = item.y,
                text = item.text,
                yend = item.yend,
                blank_line_before = prev_y ~= nil
                    and blank_line_between(self, prev_y, item.y),
            }
        )
        prev_y = item.yend
    end
    return comments
end

-- Record each comment as emitted on the stream's ledger and return the list
-- unchanged so an accessor can `return consume(self, ...)` inline. The
-- per-statement sweep consults the ledger to find comments no slot took.
local function consume(self: CommentSlots, comments: {ast.Comment}): {ast.Comment}
    for k = 1, #comments do
        self.tokens:mark_consumed(comments[k].y, comments[k].x)
    end
    return comments
end

-- Every comment inside a statement's token span that no slot emitted. The
-- default-drop model would lose these -- an unread comment trips the audit and the
-- whole file safe-skips -- so the block_doc statement sweep relocates them to the
-- statement's own-line leading, the only idempotent home for several at once: a
-- relocated comment re-lexes there as a leading comment the next run reads back the
-- same way, and own lines never join (the trailing slot would merge two line
-- comments into one). Block comments relocate too -- a block stranded mid-statement
-- (on a discarded `;`, say) would otherwise drop. take_unconsumed marks each stray
-- consumed, so an enclosing statement's sweep skips it.
function CommentSlots:unconsumed_comments_in_span(node: ast.HasTokenSpan): {ast.Comment}
    if node.tok_first == nil or node.tok_last == nil then
        return EMPTY_COMMENTS
    end
    local last = math.min(node.tok_last, #self.tokens)
    local strays = self.tokens:take_unconsumed(
        node.tok_first, last, self.fmt_off_regions
    )
    return comments_from_trivia(self, strays, nil)
end

-- The same-line comments the lexer parked right after a node's opener token (its
-- `then`/`do`/`=`/`in`/`until`/`(`/`:`). slot_tok records the opener index per
-- opener-anchored slot (head/after_opener), so the comments are that token's
-- trailing trivia.
function CommentSlots:opener_comments(
    node: ast.HasOpenerSlots, slot: ast.InlineSlot
): {ast.Comment}
    local tok_index = node.slot_tok and node.slot_tok[slot]
    if tok_index == nil then
        return EMPTY_COMMENTS
    end
    return consume(
        self, comments_from_trivia(self, self.tokens[tok_index].trailing_trivia, nil)
    )
end

local function extend<T>(into: {T}, more: {T})
    for k = 1, #more do
        into[#into + 1] = more[k]
    end
end

-- Shared empty run for the common no-trailing-trivia case, so the geometry walk
-- (trailing_extent on every node) does not allocate per node. Never mutated.
local EMPTY_TRIVIA: {token_stream.Trivia} = {}

-- The line (non-block) comments in a trivia run. A line comment after a list
-- separator trails the item before it, and one before a separator (on the item's
-- own last token, when the separator sits on the next line) trails that item too;
-- a block comment in those spots has no inline home, so the per-statement sweep
-- relocates it to the statement's leading. So the two trailing reads that look
-- across a separator take line comments only.
-- The furthest line a trivia run reaches, folded into `extent` so a caller can
-- measure several runs into one answer.
local function trivia_extent(trivia: {token_stream.Trivia}, extent: integer): integer
    for k = 1, #trivia do
        if trivia[k].yend > extent then
            extent = trivia[k].yend
        end
    end
    return extent
end

local function line_trivia(trivia: {token_stream.Trivia}): {token_stream.Trivia}
    local result: {token_stream.Trivia} = {}
    for k = 1, #trivia do
        if not trivia_doc.is_block_comment(trivia[k].text) then
            table.insert(result, trivia[k])
        end
    end
    return result
end

-- Whether a token index feeds one of this node's recorded opener slots (a bare
-- `return`'s own keyword, say). Such a token's same-line trivia is that slot, read
-- via opener_comments, so the statement-trailing read skips it rather than read it
-- twice.
local function feeds_opener_slot(node: ast.HasOpenerSlots, index: integer): boolean
    if node.slot_tok == nil then
        return false
    end
    for _, slot_index in pairs(node.slot_tok) do
        if slot_index == index then
            return true
        end
    end
    return false
end

-- The comments in a token gap, read from both sides as the lexer split them:
-- same-line ones trail the left token, own-line ones lead the right token, in
-- that source order. The op slots span a one-token gap, so a single call gathers
-- the whole gap.
local function gap_comments(
    self: CommentSlots, left_index: integer, right_index: integer
): {ast.Comment}
    local left = self.tokens[left_index]
    local right = self.tokens[right_index]
    local before = left ~= nil and left.trailing_trivia or EMPTY_TRIVIA
    local after = right ~= nil and right.leading_trivia or EMPTY_TRIVIA
    -- Both sides carrying a comment is rare enough that the joined list is worth
    -- building only then; either side alone converts straight through.
    if #before == 0 then
        return comments_from_trivia(self, after, nil)
    end
    if #after == 0 then
        return comments_from_trivia(self, before, nil)
    end
    local comments: {ast.Comment} = {}
    extend(comments, comments_from_trivia(self, before, nil))
    extend(comments, comments_from_trivia(self, after, nil))
    return comments
end

-- A comment in the gap just before the node's operator token (tok_op) is its
-- op_leading; one in the gap just after is its op_trailing. Reading the gap
-- straight off the tokens keeps `a --[[c]] + b` with --[[c]] on a's trailing,
-- ahead of the `+`. An own-line entry forces the chain to break at the operator,
-- handled by the emit helper, so the runs are read flush with no blank-line
-- baseline.
function CommentSlots:op_leading_comments(node: ast.Node): {ast.Comment}
    if node.tok_op == nil then
        return EMPTY_COMMENTS
    end
    return consume(self, gap_comments(self, node.tok_op - 1, node.tok_op))
end

function CommentSlots:op_trailing_comments(node: ast.Node): {ast.Comment}
    if node.tok_op == nil then
        return EMPTY_COMMENTS
    end
    return consume(self, gap_comments(self, node.tok_op, node.tok_op + 1))
end

-- The trivia rendered after a list item, routed purely off the parser's
-- ownership stamps. A node whose tok_sep is stamped owns the separator after it
-- (`,`/table `;`/`|`): a line comment the lexer parked on the node's last token
-- (the separator having wrapped to the next line) and one parked on the
-- separator itself both trail the node, in source order; a block comment there
-- has no inline home and is left for the per-statement sweep to relocate. A
-- stamped tok_bound (the parent's `=`/`:`, or a table's `}`, right after the
-- node) ends the claim at line comments only and donates nothing. With no stamp
-- the node sits before a closer or plain code and takes its last token's
-- same-line run whole. Selection only: trailing_comments converts the run for
-- emission, while trailing_extent -- called for every node in a geometry walk --
-- reads just its reach.
local function trailing_run(
    self: CommentSlots, node: ast.HasTokenSpan
): {token_stream.Trivia}
    if node.tok_last == nil then
        return EMPTY_TRIVIA
    end
    local last = math.min(node.tok_last, #self.tokens)
    local separator: token_stream.Token
    if node.tok_sep ~= nil then
        separator = self.tokens[node.tok_sep]
    end
    if
        #self.tokens[last].trailing_trivia == 0
        and (separator == nil or #separator.trailing_trivia == 0)
    then
        return EMPTY_TRIVIA
    end
    local run: {token_stream.Trivia} = {}
    if separator ~= nil then
        extend(run, line_trivia(self.tokens[last].trailing_trivia))
        extend(run, line_trivia(separator.trailing_trivia))
    elseif node.tok_bound ~= nil then
        extend(run, line_trivia(self.tokens[last].trailing_trivia))
    else
        extend(run, self.tokens[last].trailing_trivia)
    end
    return run
end

function CommentSlots:trailing_comments(node: ast.HasTokenSpan): {ast.Comment}
    return consume(self, comments_from_trivia(self, trailing_run(self, node), nil))
end

-- The same-line block comments in the gap just before a node's recorded opener
-- token (the `=` of an assignment or declaration), keeping `i, t --[[c]] = f(i)`
-- inline in place. Positional twin of opener_comments: that reads the trivia
-- after the opener, this reads the trivia before it. Only a run of single-line
-- block comments qualifies -- a line comment or multiline block cannot sit flush
-- before the opener, so the run is left unconsumed for trailing_comments (line
-- comments) and the per-statement sweep (stray blocks).
function CommentSlots:pre_opener_block_comments(
    node: ast.HasOpenerSlots, slot: ast.InlineSlot
): {ast.Comment}
    local tok_index = node.slot_tok and node.slot_tok[slot]
    if tok_index == nil or tok_index <= 1 then
        return EMPTY_COMMENTS
    end
    local run = self.tokens[tok_index - 1].trailing_trivia
    if #run == 0 then
        return EMPTY_COMMENTS
    end
    for k = 1, #run do
        local trivium = run[k]
        if
            not trivia_doc.is_block_comment(trivium.text) or trivium.yend ~= trivium.y
        then
            return EMPTY_COMMENTS
        end
    end
    return consume(self, comments_from_trivia(self, run, nil))
end

-- The caller emits this run after the whole lhs, so a claim bounded by anything but
-- the opener lands the comment where the source never had it: the lexer parks
-- `local x -- c` on `x` even when `: T` follows, and a comment moved past that `:`
-- re-parses onto a different token, so the next pass formats the file differently.
-- Declined, the run falls to the sweep.
function CommentSlots:pre_opener_trailing_comments(
    node: ast.HasOpenerSlots, slot: ast.InlineSlot, item: ast.HasTokenSpan
): {ast.Comment}
    local tok_index = node.slot_tok and node.slot_tok[slot]
    if tok_index == nil or item.tok_bound ~= tok_index then
        return EMPTY_COMMENTS
    end
    return self:trailing_comments(item)
end

-- The furthest source line a node's trailing comments reach, for source-extent
-- geometry (frozen-run partitioning, fmt-off overlap). A geometry read, not an
-- emission: it must NOT consume, or it would mark a comment taken that no slot
-- emits -- an expression-interior `b -- c` is read here for every node in the
-- extent walk -- and the per-statement sweep, which relocates exactly the
-- unconsumed strays, would skip it and let it drop.
function CommentSlots:trailing_extent(node: ast.HasTokenSpan): integer
    return trivia_extent(trailing_run(self, node), 0)
end

-- The last source line a node's leading comment run reaches, 0 when it has none:
-- the same window item_leading_comments reads, measured instead of converted.
-- Geometry, not emission, exactly as trailing_extent is to trailing_comments --
-- blank-line marking runs before the render and must leave these comments on the
-- ledger for the renderer that will actually emit them.
function CommentSlots:leading_extent(
    item: ast.HasTokenSpan, prev: ast.HasTokenSpan, absorb_opener?: boolean
): integer
    if item.tok_first == nil then
        return 0
    end
    local prev_end = item.tok_first - 1
    if prev ~= nil and prev.tok_last ~= nil then
        prev_end = prev.tok_last
    end
    local extent = 0
    local before = self.tokens[prev_end]
    if absorb_opener == true and before ~= nil then
        extent = trivia_extent(before.trailing_trivia, extent)
    end
    for k = math.max(prev_end + 1, 1), item.tok_first do
        extent = trivia_extent(self.tokens[k].leading_trivia, extent)
    end
    return extent
end

-- The genuine same-line trailing comments of a statement: those parked after
-- its last token (`local x = 1 -- c`; the parser deleted any discarded `;`, so
-- tok_last is always the last content token). The read skips a token that
-- feeds an opener slot (a bare `return --[[c]]` keeps its comment in
-- after_opener, read elsewhere). A line comment stranded on an earlier token
-- (after the opening keyword, a header-run keyword, or a declaration's `=`) is
-- left unconsumed for the per-statement sweep to relocate to the statement's
-- own-line leading: the trailing slot joins its run on one line
-- (trailing_comment_doc), where a non-last line comment would swallow whatever
-- follows it.
function CommentSlots:statement_trailing_comments(node: ast.Node): {ast.Comment}
    if node.tok_first == nil or node.tok_last == nil then
        return EMPTY_COMMENTS
    end
    local last = math.min(node.tok_last, #self.tokens)
    if feeds_opener_slot(node, last) then
        return EMPTY_COMMENTS
    end
    return consume(
        self, comments_from_trivia(self, self.tokens[last].trailing_trivia, nil)
    )
end

-- Append a run of comments and return the advanced blank-line baseline: the run's
-- last comment end line, so a following own-line run measures its gap from the
-- last comment rather than from the token in between. An empty run, or a
-- suppressed baseline (nil, for the leading edge of a file where nothing leads
-- with a blank), leaves the baseline unchanged.
local function append_run(
    into: {ast.Comment}, run: {ast.Comment}, prev_y: integer | nil
): integer | nil
    extend(into, run)
    if prev_y == nil or #run == 0 then
        return prev_y
    end
    return run[#run].yend
end

-- The own-line comments leading a statement or container item: the run on its
-- first token's leading trivia, plus the own-line leading stranded on a list
-- separator in the sibling gap `(prev_end, first)` -- a separator's same-line
-- trailing belongs to the previous item (trailing_comments), so no token in
-- the gap needs classifying. blank_line_before for each own-line run is
-- measured from the token before it. `absorb_opener` additionally takes the
-- same-line comment trailing the boundary token (a `{ --[[c]]` opener for a
-- first item).
local function leading_run(
    self: CommentSlots, prev_end: integer, first: integer, absorb_opener: boolean
): {ast.Comment}
    local before = self.tokens[prev_end]
    local prev_y = before and before.y or nil
    local comments: {ast.Comment} = {}
    if absorb_opener and before ~= nil then
        prev_y = append_run(
            comments, comments_from_trivia(self, before.trailing_trivia, nil), prev_y
        )
    end
    for k = prev_end + 1, first - 1 do
        prev_y = append_run(
            comments,
            comments_from_trivia(self, self.tokens[k].leading_trivia, prev_y),
            prev_y
        )
    end
    append_run(
        comments,
        comments_from_trivia(self, self.tokens[first].leading_trivia, prev_y),
        prev_y
    )
    return comments
end

-- Every comment leading a statement: its first token's leading run (the parser
-- deleted any discarded `;` between statements, moving its comments to the
-- token that follows). require_sort relocates comments contrary to source
-- order, so for the nodes it reordered the override map is authoritative.
function CommentSlots:leading_comments(node: ast.Node): {ast.Comment}
    local override = self.leading_overrides[node]
    if override ~= nil then
        return consume(self, override)
    end
    if node.tok_first == nil then
        return EMPTY_COMMENTS
    end
    return consume(self, leading_run(self, node.tok_first - 1, node.tok_first, false))
end

-- The token the dangling scan opens at: the physically last token any statement
-- spans to, or — for an empty block — the opener, so a stray `;` between the opener
-- and closer is still swept while the opener's own same-line trivia is left for the
-- after_opener slot. Taken as the max child tok_last rather than the last array
-- element, since require_sort reorders the array in place while the token indices
-- keep their original source order.
local function dangling_scan_start(node: ast.Node): integer
    local start = node.tok_first or 0
    for k = 1, #node do
        local child = node[k]
        if child.tok_last ~= nil and child.tok_last > start then
            start = child.tok_last
        end
    end
    return start
end

-- Every comment sitting after a block's last statement and before its closing
-- token. tok_last is exactly the block's closer (`end`/`until`/`else`/`elseif`), or
-- EOF for the top-level block, whose leading trivia is the file's trailing comments.
-- The lexer parks a comment on the token that follows it, so reading this
-- inter-token span in source order reproduces the dangling rule.
--
-- The scan must start past the block's own children, whose last token's trivia is
-- theirs to claim (for a nested-block child, its closer's leading) -- but an empty
-- block scans from its first token inclusive, since a stray on a deleted `;` parks
-- there. render_block_doc calls this before its statement loop, so the children
-- have not claimed anything yet and the start cannot be derived from the ledger.
--
-- The read is unconditional and must stay idempotent: a measurement pass precedes
-- the real render, so every call returns the same run. Frozen comments are not
-- filtered here -- render_block_doc drops the ones on or before its verbatim
-- boundary and keeps those past it, so a trailing `-- fmt:on` is emitted once.
function CommentSlots:dangling_comments(node: ast.Node): {ast.Comment}
    if node.tok_last == nil then
        return EMPTY_COMMENTS
    end
    local closer = math.min(node.tok_last, #self.tokens)
    local comments: {ast.Comment} = {}
    local scan_start = dangling_scan_start(node)
    if #node > 0 then
        scan_start = scan_start + 1
    end
    for k = math.max(scan_start, 1), closer - 1 do
        local before = self.tokens[k - 1]
        extend(
            comments,
            comments_from_trivia(
                self, self.tokens[k].leading_trivia, before and before.y or nil
            )
        )
        extend(
            comments, comments_from_trivia(self, self.tokens[k].trailing_trivia, nil)
        )
    end
    local prev_y = closer > 1 and self.tokens[closer - 1].y or nil
    extend(
        comments, comments_from_trivia(self, self.tokens[closer].leading_trivia, prev_y)
    )
    return consume(self, comments)
end

-- The comments a container holds after its last item and before its closing
-- token (`}` for a table, `)` for an argument or parameter list, `end` for a
-- record/enum body). tok_last is exactly that closer. The own-line comments are
-- parked as its leading trivia; unlike a statements block no discarded `;`
-- separators stand in between -- a container's separators are list `,`/`;`, whose
-- comments belong to the items they follow. `empty` containers (a `{ --[[c]] }`,
-- an empty record/enum body) additionally collect a same-line comment trailing
-- the opener, which would otherwise be a first item's leading run; with no item to
-- hold it, it dangles before the closer.
function CommentSlots:container_dangling_comments(
    node: ast.HasTokenSpan, empty?: boolean
): {ast.Comment}
    if node.tok_last == nil then
        return EMPTY_COMMENTS
    end
    local closer = math.min(node.tok_last, #self.tokens)
    local comments: {ast.Comment} = {}
    if empty and closer > 1 then
        extend(
            comments,
            comments_from_trivia(self, self.tokens[closer - 1].trailing_trivia, nil)
        )
    end
    local prev_y = closer > 1 and self.tokens[closer - 1].y or nil
    extend(
        comments, comments_from_trivia(self, self.tokens[closer].leading_trivia, prev_y)
    )
    return consume(self, comments)
end

-- The own-line comments leading a container item: its leading run plus the
-- trivia on the list separator in the gap after the previous item (`prev`, from
-- the iterating caller; nil for the first item, whose gap is empty). The first
-- item of a table or record/enum body absorbs the same-line comment trailing
-- the container's opener (`{ --[[c]]`, `record R -- c`), which the lexer hangs
-- on the opener; a parenthesized list leaves that to its after_opener slot
-- instead.
function CommentSlots:item_leading_comments(
    item: ast.HasTokenSpan, prev: ast.HasTokenSpan, absorb_opener?: boolean
): {ast.Comment}
    if item.tok_first == nil then
        return EMPTY_COMMENTS
    end
    local prev_end = item.tok_first - 1
    if prev ~= nil and prev.tok_last ~= nil then
        prev_end = prev.tok_last
    end
    return consume(
        self, leading_run(self, prev_end, item.tok_first, absorb_opener == true)
    )
end

return comment_slots
