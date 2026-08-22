-- Comment-preservation audit. Compares the comments in two versions of a file --
-- the formatter's input and its output, as their lexed token streams -- and
-- reports any the formatter dropped or duplicated. It backstops the structural
-- comment renderers, which emit a comment only when some renderer pulls its
-- trivia, so a comment no renderer claims is silently lost; the audit names which
-- one so the responsible renderer can be fixed. The caller lexes: the rewriter
-- already holds both token streams, and re-lexing here doubled its lex cost.
--
-- Comments are keyed by a whitespace-normalized form because the Doc renderer
-- strips trailing whitespace per output line and may re-indent block-comment
-- continuation lines; only a change in non-whitespace content counts as a changed
-- comment, so benign reformatting never reads as a drop.
--
-- Entry point: comment_audit.diff(before_tokens, after_tokens) -> {Problem}.
local token_stream = require("cerulean.token_stream")

local enum ProblemKind
    "dropped"
    "duplicated"
end

local record Problem
    kind: ProblemKind
    text: string
    -- The source lines where this comment appears in the input, for the message.
    lines: {integer}
end

local comment_audit = {Problem = Problem}

local function normalize(text: string): string
    local single_spaced = (text:gsub("%s+", " "))
    return (single_spaced:gsub("^ ", ""):gsub(" $", ""))
end

local function record_comment(
    counts: {string: integer}, lines: {string: {integer}}, trivium: token_stream.Trivia
)
    local key = normalize(trivium.text)
    counts[key] = (counts[key] or 0) + 1
    if lines ~= nil then
        local seen = lines[key]
        if seen == nil then
            seen = {}
            lines[key] = seen
        end
        table.insert(seen, trivium.y)
    end
end

-- Counts each comment by its normalized text. Only the input side needs the
-- source lines a comment appeared on (they go in the message), so `lines` is
-- filled when given and skipped otherwise.
local function tally(
    tokens: {token_stream.Token}, lines?: {string: {integer}}
): {string: integer}
    local counts: {string: integer} = {}
    for index = 1, #tokens do
        local token = tokens[index]
        for k = 1, #token.leading_trivia do
            record_comment(counts, lines, token.leading_trivia[k])
        end
        for k = 1, #token.trailing_trivia do
            record_comment(counts, lines, token.trailing_trivia[k])
        end
    end
    return counts
end

local function sorted_unique(values: {integer}): {integer}
    local seen: {integer: boolean} = {}
    local result: {integer} = {}
    for _, value in ipairs(values) do
        if not seen[value] then
            seen[value] = true
            table.insert(result, value)
        end
    end
    table.sort(result)
    return result
end

local KIND_ORDER: {ProblemKind: integer} = {["dropped"] = 1, ["duplicated"] = 2}

local function problem_order(first: Problem, second: Problem): boolean
    if first.text ~= second.text then
        return first.text < second.text
    end
    return KIND_ORDER[first.kind] < KIND_ORDER[second.kind]
end

function comment_audit.diff(
    before_tokens: {token_stream.Token}, after_tokens: {token_stream.Token}
): {Problem}
    local before_lines: {string: {integer}} = {}
    local before_counts = tally(before_tokens, before_lines)
    local after_counts = tally(after_tokens)
    local problems: {Problem} = {}
    for key, before_count in pairs(before_counts) do
        if (after_counts[key] or 0) < before_count then
            table.insert(
                problems,
                {kind = "dropped", text = key, lines = sorted_unique(before_lines[key])}
            )
        end
    end
    for key, after_count in pairs(after_counts) do
        if after_count > (before_counts[key] or 0) then
            table.insert(
                problems,
                {
                    kind = "duplicated",
                    text = key,
                    lines = sorted_unique(before_lines[key] or {}),
                }
            )
        end
    end
    table.sort(problems, problem_order)
    return problems
end

return comment_audit
