-- Token-level mutation for the seed-corpus fuzzing mode.
--
-- Reads real .tl files, applies a small number of random token-level
-- mutations, and writes the result back so the existing classify()
-- pipeline can process it. Most mutated inputs will be parse errors
-- (counted, ignored) — but the syntactically-valid survivors exercise
-- near-miss patterns Grammarinator does not produce.
local tl = require("tl")

local record Comment
    text: string
end

local record Token
    kind: string
    tk: string
    y: integer
    x: integer
    comments: {Comment}
end

local record Rng
    seed: integer
end

local mutate = {
    Token = Token,
    Rng = Rng,
}

function Rng.new(seed: integer | nil): Rng
    local self: Rng = setmetatable({}, {__index = Rng})
    if seed then
        math.randomseed(seed)
    end
    self.seed = seed or 0
    return self
end

function Rng:int(low: integer, high: integer): integer
    return math.random(low, high)
end

function Rng:float(): number
    return math.random()
end

local function lex_content(content: string, filename: string): {Token}
    local raw_tokens, _ = tl.lex(content, filename)
    local tokens: {Token} = {}
    if raw_tokens then
        for _, t in ipairs(raw_tokens as {Token}) do
            if t.kind ~= "$EOF$" then
                table.insert(tokens, t)
            end
        end
    end
    return tokens
end

-- Rebuild source from token list. Preserves line breaks (via y deltas) and
-- attached comments. Indentation is lost but the formatter normalises it
-- anyway.
local function detokenize(tokens: {Token}): string
    local parts: {string} = {}
    local function last_char(): string
        for i = #parts, 1, -1 do
            local p = parts[i]
            if #p > 0 then
                return p:sub(-1)
            end
        end
        return ""
    end
    local prev_y = 1
    for _, tok in ipairs(tokens) do
        if tok.comments then
            for _, c in ipairs(tok.comments) do
                local prev = last_char()
                if prev ~= "" and prev ~= "\n" then
                    table.insert(parts, "\n")
                end
                table.insert(parts, c.text)
                table.insert(parts, "\n")
            end
        end
        if tok.y and tok.y > prev_y then
            for _ = prev_y, tok.y - 1 do
                local prev = last_char()
                if prev ~= "\n" or parts[#parts] == "" then
                    table.insert(parts, "\n")
                else
                    table.insert(parts, "\n")
                end
            end
        else
            local prev = last_char()
            if prev ~= "" and prev ~= "\n" then
                table.insert(parts, " ")
            end
        end
        table.insert(parts, tok.tk)
        prev_y = tok.y or prev_y
    end
    return table.concat(parts)
end

local function mutate_delete(tokens: {Token}, rng: Rng): {Token}
    if #tokens == 0 then
        return tokens
    end
    table.remove(tokens, rng:int(1, #tokens))
    return tokens
end

local function mutate_dup(tokens: {Token}, rng: Rng): {Token}
    if #tokens == 0 then
        return tokens
    end
    local idx = rng:int(1, #tokens)
    local copy: Token = {
        kind = tokens[idx].kind,
        tk = tokens[idx].tk,
        y = tokens[idx].y,
        x = tokens[idx].x,
        comments = nil,
    }
    table.insert(tokens, idx, copy)
    return tokens
end

local function mutate_swap_adjacent(tokens: {Token}, rng: Rng): {Token}
    if #tokens < 2 then
        return tokens
    end
    local idx = rng:int(1, #tokens - 1)
    tokens[idx], tokens[idx + 1] = tokens[idx + 1], tokens[idx]
    return tokens
end

local function mutate_truncate(tokens: {Token}, rng: Rng): {Token}
    if #tokens < 2 then
        return tokens
    end
    local keep = rng:int(1, #tokens - 1)
    for i = #tokens, keep + 1, -1 do
        table.remove(tokens, i)
    end
    return tokens
end

local OPS = {
    mutate_delete,
    mutate_dup,
    mutate_swap_adjacent,
    mutate_truncate,
}

local function apply_random(tokens: {Token}, rng: Rng): {Token}
    local op = OPS[rng:int(1, #OPS)]
    return op(tokens, rng)
end

function mutate.mutated(content: string, n: integer, rng: Rng, filename: string): string
    local tokens = lex_content(content, filename)
    for _ = 1, n do
        tokens = apply_random(tokens, rng)
    end
    return detokenize(tokens)
end

return mutate
